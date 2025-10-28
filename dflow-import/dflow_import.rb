module DflowImport

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
   #   |    +--- 2021-08-03-14-53-45           (dir)
   #   |    |    +--- files                    (dir)
   #   |    |    |    +--- GUB123095.pdf       (file)
   #   |    |    |    +--- dublin_core.xml     (file)
   #   |    |    |    +--- contents            (file) Contains only the following text:          GUB0123095.pdf
   #   |    |    +--- collection               (file) Contains only the following kind of text:  2077/30573
   #   |    +--- ...
   #   |    +--- ...
   #   |
   #   +--- done                               (dir)
   #   |    +--- 2021-08-03-13-25-03           (dir)
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
   #   |    +--- 2021-08-03-14-37-58           (dir)
   #   |    |    +--- files                    (dir)
   #   |    |    |    +--- GUB123094.pdf       (file)
   #   |    |    |    +--- dublin_core.xml     (file)
   #   |    |    |    +--- contents            (file) Contains only the following text:          GUB0123094.pdf
   #   |    |    +--- collection               (file) Contains only the following kind of text:  2077/30573
   #   |    +--- ...
   #   |    +--- ...
   #   |
   #   +--- logs                               (dir)
   #        +--- handles.log                   (dir)  For content example, see HANDLE_LOG below
   #        +--- error.log                     (dir)  For content example, see ERROR_LOG below
   #

   # All of the constants that are fetched from the environment:

   # - the binary (in the DSpace Docker container) which performs the import
   DSPACE_BINARY       = ENV['DSPACE_BINARY'                ]

   # - base url for accessing the handle of the imported package
   GUPEA_URLBASE       = ENV['DFLOW_IMPORT_GUPEA_URLBASE'   ]

   # - base path in (volume mounted) DSpace Docker container, e.g., '/dspace/var/dflow/'
   #   used by the import command (executed in the DSpace Docker container) 
   BASE_PATH    = ENV['DFLOW_IMPORT_BASE_PATH']

   # - regexp used to extract the handle from the mapfile produced by the import ('files 2077/' in production)
   MAPFILE_REGEXP      = ENV['DFLOW_IMPORT_MAPFILE_REGEXP'  ]

   # - user used by the import command
   USER                = ENV['DFLOW_IMPORT_USER'            ]

   # Paths (may) differ in the import dFlow and DSpace Docker containers (but both are mounted to an external volume).
   # (Here are the paths for new and logs. The paths for done and error are built dynamically.)
   NEW_FILES_PATH   = BASE_PATH   + 'new/'
   LOG_FILES_PATH   = BASE_PATH   + 'logs/'

   # Output files:

   # - The handle log file accumulates the list of successful imports, e.g.,:
   #      time: 2015-03-20 11:08:21, dflow_id: 104613, url: http://hdl.handle.net/2077/38541
   #      time: 2015-03-20 11:08:31, dflow_id: 104614, url: http://hdl.handle.net/2077/38542
   #      time: 2015-03-20 11:08:40, dflow_id: 104618, url: http://hdl.handle.net/2077/38543
   HANDLE_LOG = LOG_FILES_PATH + "handles.log"

   # - A short extract from the error log may look as follows (as is evident, the extra_info field may be empty):
   #      time: 2016-01-20 15:50:08, dflow_id: 105096, msg: Package not found, extra_info: 
   #      time: 2016-01-25 15:01:00, dflow_id: 104940, msg: The package is probably already imported, extra_info: time: 2016-01-25 15:00:53, dflow_id: 104940, url: http://hdl.handle.net/2077/41641
   #      time: 2016-02-02 18:00:44, dflow_id: 105364, msg: Mapfile content error, handle could not be found, extra_info: 
   ERROR_LOG  = LOG_FILES_PATH + "error.log"

   # Command to the DSpace binary
   IMPORT_CMD = "#{DSPACE_BINARY} import"

   # Extracts from strings produced by DSpace, telling the outcome of the import 
   SUCCESS_STR            = "It appears there is no handle file -- generating one"
   ENTITY_ERROR_STR       = "org.xml.sax.SAXParseException: The entity name must immediately follow the "
   COLLECTIONID_ERROR_STR = "java.lang.IllegalArgumentException: Cannot resolve "
   FIELD_ERROR_STR        = "ERROR: Metadata field: "

   # Error reporting
   NO_EXTRA_INFO = ""


   ###################
   # Starting point

   def self.run(params, app)

      # Parameter validation (only one parameter, the dflow id, is expected and used)
      dflow_id = params[:id]
      validate_dflow_id(dflow_id, app)

      # Basic paths (in the import dFlow container)
      import_root_dir  = NEW_FILES_PATH + dflow_id
      import_files_dir = import_root_dir     + "/files/"
      collection_file  = import_root_dir     + "/collection"
      mapfile          = import_root_dir     + "/mapfile"     
  
      # Basic checks
      check_if_package_is_already_imported(dflow_id, app)
      check_directory_and_file_structure(import_root_dir, import_files_dir, collection_file, dflow_id, app)

      # Import
      collection_handle = extract_collection_handle(collection_file, dflow_id, app)
      import_to_dspace(dflow_id, collection_handle, app)
      package_handle = extract_package_handle(mapfile, dflow_id, app)

      # If we have reached this far we know that the import was successful
      # and we can do the chores we hoped for.
      move_to_done(dflow_id)
      url = get_url(package_handle)
      write_to_handle_log_file(dflow_id, url)
      send_response_success(dflow_id, url, app)

   end


   ################################
   # Basic validation and checks

   private_class_method def self.validate_dflow_id(dflow_id, app)
      if dflow_id !~ /^\d+$/ 
         handle_id_validation_error(-1, "The dflow id is not valid", "dflow id: #{dflow_id}", app)
      end
   end

   private_class_method def self.check_if_package_is_already_imported(dflow_id, app)
      # Package is probably already imported if it is logged in the handle log file,
      # i.e., grep for the dflow_id in among the following kind of entries:
      # time: 2015-03-20 11:08:21, dflow_id: 104613, url: http://hdl.handle.net/2077/38541
      grep_result = File.readlines(HANDLE_LOG).grep(Regexp.new("dflow_id: #{dflow_id}, "))
      if grep_result[0]
         handle_server_error(dflow_id, "The package is probably already imported", grep_result[0].chomp, app)
      end
   end

   private_class_method def self.check_directory_and_file_structure(import_root_dir, import_files_dir, collection_file, dflow_id, app)
      if !File.directory?(import_root_dir)
         handle_server_error(dflow_id, "Package not found"  , NO_EXTRA_INFO, app)
      end
      if !File.directory?(import_files_dir)
         move_to_error(dflow_id, "Files directory not found", NO_EXTRA_INFO, app)
      end
      if !File.exist?(collection_file)
         move_to_error(dflow_id, "Collection file not found", NO_EXTRA_INFO, app)
      end
   end


   ########################
   # Get handles and url

   # Collection handles exist already before the import
   private_class_method def self.extract_collection_handle(collection_file, dflow_id, app)
      # Get the collection handle
      file = File.open(collection_file, "rb")
      collection_handle = file.read.chomp
      file.close

      # Check format of the content, should be like, e.g., 2077/30573  
      if !(collection_handle =~ /^2077\/\d+$/)
         move_to_error(dflow_id, "Format error in collection file", "collection handle: #{collection_handle}", app)
      end

      # No errors, return the collection handle
      collection_handle
   end

   # Mapfiles exist after the import. Contains a short text of the following type: files 2077/40275
   private_class_method def self.extract_package_handle(mapfile, dflow_id, app)
      if File.exist?(mapfile)
         mapcontent = File.readlines(mapfile).grep(Regexp.new(MAPFILE_REGEXP))
         if mapcontent[0]
            handle = mapcontent[0].gsub("files ", "").chomp
         else 
            move_to_error(dflow_id, "Mapfile content error, handle could not be found", NO_EXTRA_INFO, app)
         end     
      else
          move_to_error(dflow_id, "Mapfile is missing, handle could not be found", NO_EXTRA_INFO, app)
      end
      handle
   end
  
   # The URL to be returned in the success response and written to the handle log after successful import,
   # e.g., "http://hdl.handle.net/2077/40275"
   private_class_method  def self.get_url(handle)
      "#{GUPEA_URLBASE}#{handle}"
   end


   #################################
   # Import and check the outcome

   # This method is the only location where external communication with the DSpace CLI takes place
   private_class_method  def self.import_to_dspace(dflow_id, collection_handle, app)
  
      # Paths in the DSpace container
      import_root_dir_dspace = NEW_FILES_PATH + dflow_id
      mapfile_dspace = import_root_dir_dspace + "/mapfile"

      # Import by executing the DSpace CLI import command in the DSpace container
      import_command = IMPORT_CMD       + 
                       " --add"         + 
                       " --eperson="    + USER                   + 
                       " --collection=" + collection_handle      + 
                       " --source="     + import_root_dir_dspace + 
                       " --mapfile="    + mapfile_dspace         + 
                       " 2>&1"
      import_result = %x[#{import_command}]
   
      # Check the result message generated in the DSpace container for errors
      check_import_result_for_errors(import_result, dflow_id, app)
   end

   private_class_method def self.check_import_result_for_errors(import_result, dflow_id, app)
      if import_result.include?(SUCCESS_STR)
         return "Success" # Not actually used outside
      elsif import_result.include?(ENTITY_ERROR_STR)
         move_to_error(dflow_id, "DSpace import script error, entity error in dublin_core.xml"        , import_result, app)
      elsif import_result.include?(FIELD_ERROR_STR)
         move_to_error(dflow_id, "DSpace import script error, metadata field error in dublin_core.xml", import_result, app)
      elsif import_result.include?(COLLECTIONID_ERROR_STR)
         move_to_error(dflow_id, "DSpace import script error, unknown collection handle"              , import_result, app)
      else
         move_to_error(dflow_id, "Unknown import error from DSpace import script"                     , import_result, app)
      end 
   end


   ################################
   # Register successful imports
   
   # E.g.: "time: 2015-03-20 11:08:21, dflow_id: 104613, url: http://hdl.handle.net/2077/38541"
   private_class_method def self.write_to_handle_log_file(dflow_id, url)
      handle_log_file = File.open(HANDLE_LOG, 'a')
      handle_log_file.puts("time: "     + Time.new.strftime("%Y-%m-%d %H:%M:%S") + ", " + 
                           "dflow_id: " + dflow_id                               + ", " + 
                           "url: "      + url + "\n")
      handle_log_file.close
   end
  

   ###############
   # Move files

   private_class_method def self.move_to_error(dflow_id, error_msg, extra_error_info, app)
      move_dir(NEW_FILES_PATH + dflow_id, NEW_FILES_PATH, "error")
      handle_server_error(dflow_id, error_msg, extra_error_info, app)
   end

   private_class_method def self.move_to_done(dflow_id)
      move_dir(NEW_FILES_PATH + dflow_id, NEW_FILES_PATH, "done")
   end

   private_class_method def self.move_dir(src_dir, base_path, mode)
      tgt_dir = File.dirname(base_path) + "/" + mode + "/" + Time.new.strftime("%Y-%m-%d--%H-%M-%S") + "/" 
      FileUtils.mkdir_p(tgt_dir)
      # E.g.: FileUtils.mv('/data/import/new/123095', '/data/import/done/2021-08-05--14-53-47/')
      #       resulting in the new location /data/import/done/2021-08-05--14-53-47/123095
      FileUtils.mv(src_dir, tgt_dir)
   end


   ##################
   # Send response

   private_class_method def self.send_response_success(dflow_id, url, app)
      app.halt 200, {:id => "#{dflow_id}", :url => url}.to_json
   end
  
   private_class_method def self.send_response_validation_error(msg, extra_info, app)
      app.halt 400, {:error => "#{msg}", :extra_info => "#{extra_info}"}.to_json
   end
  
   private_class_method def self.send_response_server_error(msg, extra_info, app)
      app.halt 500, {:error => "#{msg}", :extra_info => "#{extra_info}"}.to_json
   end


   ##################
   # Handle errors

   private_class_method def self.handle_server_error(id, msg, extra_info, app)
      write_to_error_log_file(id, msg, extra_info)
      send_response_server_error(msg, extra_info, app)
   end

   private_class_method def self.handle_id_validation_error(id, msg, extra_info, app)
      write_to_error_log_file(id, msg, extra_info)
      send_response_validation_error(msg, extra_info, app)
   end

   private_class_method def self.write_to_error_log_file(id, msg, extra_info)
      error_log_file = File.open(ERROR_LOG, 'a')
      error_log_file.puts("time: "       + Time.new.strftime("%Y-%m-%d %H:%M:%S") + ", " + 
                          "dflow_id: "   + id.to_s                                + ", " + 
                          "msg: "        + msg                                    + ", " + 
                          "extra_info: " + extra_info                             + "\n")
      error_log_file.close
   end

end

