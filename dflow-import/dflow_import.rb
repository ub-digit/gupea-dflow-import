module DflowImport
  include SemanticLogger::Loggable

  # This module is responsible for the import of dFlow files to DSpace.
  # It presumes a DSpace Docker container with an ssh server and the appropriate key
  # installed (and of course an ssh client, keys and an entry for the host in
  # known_hosts in a import dFlow container hosting this DflowImport module).
  #
  # For communication it uses the DSpace CLI which is invoked through ssh.
  # Another means of communication which also has to be set up is a dual volume binding.
  # Both the dFlow container, that hosts this module, and the DSpace container
  # should have a volume binding to the same external directory (i.e., outside of Docker),
  # e.g., a directory '/dspace/var/dflow/' in the DSpace container and a '/data/import/'
  # in the import dFlow container '/data/import/' should both be linked to an external
  # directory like '/data/gupea/import/dflow/'. The three directories are supplied to
  # this module by environment variables, and hence are configurable.
  #
  # The file packages to be imported should be placed in the 'new' directory of the
  # external directory. After DflowImport.run is invoked, the package will be moved to
  # the 'done' directory, if the import was successful, or the 'error' directory, if
  # there were any errors. An additional 'mapfile' file containing an external handle
  # will be created and added to successful file packages. The package then can be accessed
  # using an url like, e.g., http://hdl.handle.net/2077/68635, where 2077/68635 is the handle.
  #
  # If the import was successful there will also be a new entry in the 'handles.log' file.
  # The handles log file is checked before each new import, and if the package to be imported
  # already seems to be imported it will be considered an error and no import will take place.
  # Generally, different error states may be encountered, and when an error occurs,
  # the execution will halt, an error message is added to the 'error.log' file, and
  # an error json is sent as response to the web request.

  # Tree example:
  #   +--- new                                (dir)
  #   |    +--- 523523                        (dir)
  #   |    |    +--- files                    (dir)
  #   |    |    |    +--- GUB123095.pdf       (file)
  #   |    |    |    +--- dublin_core.xml     (file)
  #   |    |    |    +--- contents            (file) Contains only the following text:          GUB0123095.pdf
  #   |    |    +--- collection               (file) Contains only the following kind of text:  2077/30573
  #   |    +--- ...
  #   |    +--- ...
  #   |
  #   +--- done                               (dir)
  #   |    +--- 12341                         (dir)
  #   |    |    +--- files                    (file)
  #   |    |    |    +--- GUB123093.pdf       (file)
  #   |    |    |    +--- dublin_core.xml     (file)
  #   |    |    |    +--- contents            (file) Contains only the following text:          GUB0123093.pdf
  #   |    |    +--- collection               (file) Contains only the following kind of text:  2077/30573
  #   |    |    +--- mapfile                  (file) Contains only the following kind of text:  files 2077/68635
  #   |    +--- ...
  #   |    +--- ...
  #   |
  #   +--- error                              (dir)
  #        +--- 12345                         (dir)
  #        |    +--- files                    (dir)
  #        |    |    +--- GUB123094.pdf       (file)
  #        |    |    +--- dublin_core.xml     (file)
  #        |    |    +--- contents            (file) Contains only the following text:          GUB0123094.pdf
  #        |    +--- collection               (file) Contains only the following kind of text:  2077/30573
  #        +--- ...
  #        +--- ...
  #

  # All of the constants that are fetched from the environment:

  # - the binary (in the DSpace Docker container) which performs the import
  DSPACE_BINARY = ENV['DSPACE_BINARY']

  # - base url for accessing the handle of the imported package
  GUPEA_URLBASE = ENV['DFLOW_IMPORT_GUPEA_URLBASE']

  # - base path in (volume mounted) DSpace Docker container, e.g., '/dspace/var/dflow/'
  #   used by the import command (executed in the DSpace Docker container) 
  BASE_PATH = ENV['DFLOW_IMPORT_BASE_PATH']

  # - regexp used to extract the handle from the mapfile produced by the import ('files 2077/' in production)
  MAPFILE_REGEXP = ENV['DFLOW_IMPORT_MAPFILE_REGEXP']

  # - user used by the import command
  USER = ENV['DFLOW_IMPORT_USER']

  # Paths (may) differ in the import dFlow and DSpace Docker containers (but both are mounted to an external volume).
  # (Here are the paths for new and logs. The paths for done and error are built dynamically.)
  NEW_FILES_DIR = File.join(BASE_PATH, 'new')
  FAILED_FILES_DIR = File.join(BASE_PATH, 'error')
  DONE_FILES_DIR = File.join(BASE_PATH, 'done')


  # Command to the DSpace binary
  IMPORT_CMD = "#{DSPACE_BINARY} import"

  # Extracts from strings produced by DSpace, telling the outcome of the import
  SUCCESS_STR            = "It appears there is no handle file -- generating one"
  ENTITY_ERROR_STR       = "org.xml.sax.SAXParseException: The entity name must immediately follow the "
  COLLECTIONID_ERROR_STR = "java.lang.IllegalArgumentException: Cannot resolve "
  FIELD_ERROR_STR        = "ERROR: Metadata field: "


  ###################
  # Starting point

  def self.run(params, app)

    # Parameter validation (only one parameter, the dflow id, is expected and used)
    dflow_id = params[:id]
    validate_dflow_id(dflow_id, app)

    # Basic paths (in the import dFlow container)
    import_root_dir  = File.join(NEW_FILES_DIR, dflow_id)
    import_files_dir = File.join(import_root_dir, "files")
    collection_file  = File.join(import_root_dir, "collection")
    mapfile          = File.join(import_root_dir, "mapfile")

    # Basic checks
    check_if_package_is_already_imported(dflow_id, app)
    check_directory_and_file_structure(import_root_dir, import_files_dir, collection_file, dflow_id, app)

    # Import
    if File.exist?(collection_file)
      collection_handle = extract_collection_handle(collection_file)
      # Check format of the content, should be like, e.g., 2077/30573
      if !(collection_handle =~ /^2077\/\d+$/)
        move_to_error(dflow_id, "Format error in collection file, collection handle: #{collection_handle}", app)
      end
    else
      move_to_error(dflow_id, "Collection file is missing, handle could not be found", app)
    end

    if File.exist?(mapfile)
      package_handle = extract_package_handle(mapfile)
      if !package_handle
        move_to_error(dflow_id, "Mapfile content error, handle could not be found", app)
      end
    else
      move_to_error(dflow_id, "Mapfile is missing, handle could not be found", app)
    end

    import_to_dspace(dflow_id, collection_handle, mapfile, app)

    # If we have reached this far we know that the import was successful
    # and we can do the chores we hoped for.
    move_to_done(dflow_id)
    url = get_url(package_handle)
    write_to_handle_log_file(dflow_id, url)

    logger.info("time: "     + Time.new.strftime("%Y-%m-%d %H:%M:%S") + ", " +
                "dflow_id: " + dflow_id                               + ", " +
                "url: "      + url + "\n")

    send_response_success(dflow_id, url, app)
  end

  ################################
  # Basic validation and checks

  private_class_method def self.validate_dflow_id(dflow_id, app)
    if dflow_id !~ /^\d+$/
      handle_id_validation_error(-1, "The dflow id is not valid", app)
    end
  end

  private_class_method def self.check_if_package_is_already_imported(dflow_id, app)
    if Dir.exist?(File.join(DONE_FILES_DIR, dflow_id))
      message = "The package with dflow-id #{dflow_id} is probably already imported"
      mapfile = File.join(DONE_FILES_DIR, dflow_id, "mapfile")
      if File.exists(mapfile)
        package_handle = extract_package_handle(mapfile)
        if package_handle
          url = get_url(package_handle)
          message += ", url: #{url}"
        else
          message += ', but the imported package has invalid mapfile content'
        end
      else
          message += ', but the imported package is missing a mapfile'
      end
      handle_server_error(dflow_id, message, app)
    end
  end

  private_class_method def self.check_directory_and_file_structure(import_root_dir, import_files_dir, collection_file, dflow_id, app)
    if !File.directory?(import_root_dir)
      handle_server_error(dflow_id, "Package not found", app)
    end
    if !File.directory?(import_files_dir)
      move_to_error(dflow_id, "Files directory not found", app)
    end
    if !File.exist?(collection_file)
      move_to_error(dflow_id, "Collection file not found", app)
    end
  end

  ########################
  # Get handles and url

  # Collection handles exist already before the import
  private_class_method def self.extract_collection_handle(collection_file)
    # Get the collection handle
    file = File.open(collection_file, "rb")
    collection_handle = file.read.chomp
    file.close
    collection_handle
  end

  # Mapfiles exist after the import. Contains a short text of the following type: files 2077/40275
  private_class_method def self.extract_package_handle(mapfile)
    mapcontent = File.readlines(mapfile).grep(Regexp.new(MAPFILE_REGEXP))
    mapcontent[0].gsub("files ", "").chomp if mapcontent[0]
  end

  # The URL to be returned in the success response and written to the handle log after successful import,
  # e.g., "http://hdl.handle.net/2077/40275"
  private_class_method  def self.get_url(handle)
    "#{GUPEA_URLBASE}#{handle}"
  end

  #################################
  # Import and check the outcome

  # This method is the only location where external communication with the DSpace CLI takes place
  private_class_method  def self.import_to_dspace(dflow_id, collection_handle, mapfile, app)

    # Import by executing the DSpace CLI import command in the DSpace container
    import_command = IMPORT_CMD                 +
      " --add"         +
      " --eperson="    + USER                   +
      " --collection=" + collection_handle      +
      " --source="     + import_root_dir_dspace +
      " --mapfile="    + mapfile                +
      " 2>&1"
    import_result = %x[#{import_command}]

    # Check the result message generated in the DSpace container for errors
    check_import_result_for_errors(import_result, dflow_id, app)
  end

  private_class_method def self.check_import_result_for_errors(import_result, dflow_id, app)
    if import_result.include?(SUCCESS_STR)
      return
    elsif import_result.include?(ENTITY_ERROR_STR)
      move_to_error(dflow_id, "DSpace import script error, entity error in dublin_core.xml: '#{import_result}'", app)
    elsif import_result.include?(FIELD_ERROR_STR)
      move_to_error(dflow_id, "DSpace import script error, metadata field error in dublin_core.xml: '#{import_result}'", app)
    elsif import_result.include?(COLLECTIONID_ERROR_STR)
      move_to_error(dflow_id, "DSpace import script error, unknown collection handle: '#{import_result}'", app)
    else
      move_to_error(dflow_id, "Unknown import error from DSpace import script: '#{import_result}'", app)
    end
  end


  ################################
  # Register successful imports

  ###############
  # Move files

  private_class_method def self.move_to_error(dflow_id, msg, app)
    FileUtils.mv(File.join(NEW_FILES_DIR, dflow_id), FAILED_FILES_DIR);
    handle_server_error(dflow_id, msg, app)
  end

  private_class_method def self.move_to_done(dflow_id)
    FileUtils.mv(File.join(NEW_FILES_DIR, dflow_id), DONE_FILES_DIR);
  end

  ##################
  # Send response

  private_class_method def self.send_response_success(dflow_id, url, app)
    app.halt 200, {:id => "#{dflow_id}", :url => url}.to_json
  end

  private_class_method def self.send_response_validation_error(msg, app)
    app.halt 400, {:error => msg}.to_json
  end

  private_class_method def self.send_response_server_error(msg, app)
    app.halt 500, {:error => msg}.to_json
  end


  ##################
  # Handle errors

  private_class_method def self.handle_server_error(dflow_id, msg, app)
    log_error(dflow_id, msg)
    send_response_server_error(msg, app)
  end

  private_class_method def self.handle_id_validation_error(dflow_id, msg, app)
    log_error(dflow_id, msg)
    send_response_validation_error(msg, app)
  end

  private_class_method def self.log_error(dflow_id, msg)
    logger.error("#{msg}, dflow_id: #{dflow_id}")
  end
end
