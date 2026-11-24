import os
import re
import shlex
import shutil
import subprocess
from datetime import datetime
from flask import Flask, jsonify

app = Flask(__name__)

# Environment configuration
DSPACE_BINARY = os.environ["DSPACE_BINARY"]
GUPEA_URLBASE = os.environ["DFLOW_IMPORT_GUPEA_URLBASE"]
BASE_PATH = os.environ["DFLOW_IMPORT_BASE_PATH"].rstrip("/")
MAPFILE_REGEXP = os.environ["DFLOW_IMPORT_MAPFILE_REGEXP"]
USER = os.environ["DFLOW_IMPORT_USER"]

# Derived paths
NEW_FILES_PATH = os.path.join(BASE_PATH, "new")
LOG_FILES_PATH = os.path.join(BASE_PATH, "logs")
HANDLE_LOG = os.path.join(LOG_FILES_PATH, "handles.log")
ERROR_LOG = os.path.join(LOG_FILES_PATH, "error.log")

# DSpace CLI output markers
SUCCESS_STR = "It appears there is no handle file -- generating one"
ENTITY_ERROR_STR = "org.xml.sax.SAXParseException: The entity name must immediately follow the "
COLLECTIONID_ERROR_STR = "java.lang.IllegalArgumentException: Cannot resolve "
FIELD_ERROR_STR = "ERROR: Metadata field: "
NO_EXTRA_INFO = ""


class ImportHaltError(Exception):
    """Replicates Sinatra's `halt` to immediately return an HTTP error response."""

    def __init__(self, status_code: int, msg: str, extra_info: str = ""):
        super().__init__(msg)
        self.status_code = status_code
        self.msg = msg
        self.extra_info = extra_info


class DflowImport:
    @classmethod
    def run(cls, dflow_id: str):
        cls._validate_dflow_id(dflow_id)

        import_root_dir = os.path.join(NEW_FILES_PATH, dflow_id)
        import_files_dir = os.path.join(import_root_dir, "files")
        collection_file = os.path.join(import_root_dir, "collection")
        mapfile = os.path.join(import_root_dir, "mapfile")

        cls._check_if_package_is_already_imported(dflow_id)
        cls._check_directory_and_file_structure(
            import_root_dir, import_files_dir, collection_file, dflow_id
        )

        collection_handle = cls._extract_collection_handle(collection_file, dflow_id)
        cls._import_to_dspace(dflow_id, collection_handle)
        package_handle = cls._extract_package_handle(mapfile, dflow_id)

        cls._move_to_done(dflow_id)
        url = cls._get_url(package_handle)
        cls._write_to_handle_log_file(dflow_id, url)

        return jsonify({"id": str(dflow_id), "url": url}), 200

    # --- Basic validation and checks ---

    @classmethod
    def _validate_dflow_id(cls, dflow_id: str):
        if not re.match(r"^\d+$", dflow_id):
            cls._handle_error(
                -1, "The dflow id is not valid", f"dflow id: {dflow_id}", status_code=400
            )

    @classmethod
    def _check_if_package_is_already_imported(cls, dflow_id: str):
        pattern = re.compile(rf"dflow_id: {re.escape(dflow_id)}, ")
        with open(HANDLE_LOG, "r", encoding="utf-8") as f:
            for line in f:
                if pattern.search(line):
                    cls._handle_error(
                        dflow_id,
                        "The package is probably already imported",
                        line.rstrip("\r\n"),
                        status_code=500,
                    )

    @classmethod
    def _check_directory_and_file_structure(
        cls, import_root_dir: str, import_files_dir: str, collection_file: str, dflow_id: str
    ):
        if not os.path.isdir(import_root_dir):
            cls._handle_error(dflow_id, "Package not found", NO_EXTRA_INFO, status_code=500)
        if not os.path.isdir(import_files_dir):
            cls._move_to_error(dflow_id, "Files directory not found", NO_EXTRA_INFO)
        if not os.path.isfile(collection_file):
            cls._move_to_error(dflow_id, "Collection file not found", NO_EXTRA_INFO)

    # --- Handles and URL ---

    @classmethod
    def _extract_collection_handle(cls, collection_file: str, dflow_id: str) -> str:
        with open(collection_file, "r", encoding="utf-8") as f:
            collection_handle = f.read().rstrip("\r\n")

        if not re.match(r"^2077/\d+$", collection_handle):
            cls._move_to_error(
                dflow_id,
                "Format error in collection file",
                f"collection handle: {collection_handle}",
            )
        return collection_handle

    @classmethod
    def _extract_package_handle(cls, mapfile: str, dflow_id: str) -> str:
        if not os.path.isfile(mapfile):
            cls._move_to_error(
                dflow_id, "Mapfile is missing, handle could not be found", NO_EXTRA_INFO
            )

        pattern = re.compile(MAPFILE_REGEXP)
        with open(mapfile, "r", encoding="utf-8") as f:
            for line in f:
                if pattern.search(line):
                    return line.replace("files ", "", 1).rstrip("\r\n")

        cls._move_to_error(
            dflow_id, "Mapfile content error, handle could not be found", NO_EXTRA_INFO
        )

    @staticmethod
    def _get_url(handle: str) -> str:
        return f"{GUPEA_URLBASE}{handle}"

    # --- DSpace CLI import ---

    @classmethod
    def _import_to_dspace(cls, dflow_id: str, collection_handle: str):
        import_root_dir_dspace = os.path.join(NEW_FILES_PATH, dflow_id)
        mapfile_dspace = os.path.join(import_root_dir_dspace, "mapfile")

        # DSPACE_BINARY may include an ssh prefix (e.g. "ssh user@host /dspace/bin/dspace"),
        # so shlex.split preserves multi-token commands safely.
        cmd = [
            *shlex.split(DSPACE_BINARY),
            "import",
            "--add",
            f"--eperson={USER}",
            f"--collection={collection_handle}",
            f"--source={import_root_dir_dspace}",
            f"--mapfile={mapfile_dspace}",
        ]

        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        cls._check_import_result_for_errors(result.stdout, dflow_id)

    @classmethod
    def _check_import_result_for_errors(cls, import_result: str, dflow_id: str):
        if SUCCESS_STR in import_result:
            return
        elif ENTITY_ERROR_STR in import_result:
            cls._move_to_error(
                dflow_id,
                "DSpace import script error, entity error in dublin_core.xml",
                import_result,
            )
        elif FIELD_ERROR_STR in import_result:
            cls._move_to_error(
                dflow_id,
                "DSpace import script error, metadata field error in dublin_core.xml",
                import_result,
            )
        elif COLLECTIONID_ERROR_STR in import_result:
            cls._move_to_error(
                dflow_id,
                "DSpace import script error, unknown collection handle",
                import_result,
            )
        else:
            cls._move_to_error(
                dflow_id, "Unknown import error from DSpace import script", import_result
            )

    # --- Logging ---

    @staticmethod
    def _write_to_handle_log_file(dflow_id: str, url: str):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(HANDLE_LOG, "a", encoding="utf-8") as f:
            f.write(f"time: {timestamp}, dflow_id: {dflow_id}, url: {url}\n")

    @staticmethod
    def _write_to_error_log_file(dflow_id, msg: str, extra_info: str):
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(ERROR_LOG, "a", encoding="utf-8") as f:
            f.write(
                f"time: {timestamp}, dflow_id: {dflow_id}, msg: {msg}, extra_info: {extra_info}\n"
            )

    # --- File movement ---

    @classmethod
    def _move_to_error(cls, dflow_id: str, error_msg: str, extra_error_info: str):
        cls._move_dir(os.path.join(NEW_FILES_PATH, dflow_id), "error")
        cls._handle_error(dflow_id, error_msg, extra_error_info, status_code=500)

    @classmethod
    def _move_to_done(cls, dflow_id: str):
        cls._move_dir(os.path.join(NEW_FILES_PATH, dflow_id), "done")

    @staticmethod
    def _move_dir(src_dir: str, mode: str):
        timestamp = datetime.now().strftime("%Y-%m-%d--%H-%M-%S")
        tgt_dir = os.path.join(BASE_PATH, mode, timestamp)
        os.makedirs(tgt_dir, exist_ok=True)
        shutil.move(src_dir, tgt_dir)

    # --- Error handling ---

    @classmethod
    def _handle_error(cls, dflow_id, msg: str, extra_info: str, status_code: int):
        cls._write_to_error_log_file(dflow_id, msg, extra_info)
        raise ImportHaltError(status_code, msg, extra_info)


@app.route("/dflow_import/<dflow_id>", methods=["GET"])
def dflow_import(dflow_id: str):
    try:
        return DflowImport.run(dflow_id)
    except ImportHaltError as err:
        return jsonify({"error": err.msg, "extra_info": err.extra_info}), err.status_code


if __name__ == "__main__":
    is_dev = os.environ.get("FLASK_ENV", "development") == "development"
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 3000)), debug=is_dev)
