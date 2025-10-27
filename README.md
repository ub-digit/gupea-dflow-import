# Gupea-ext-import-dflow

Gupea-ext-import-dflow extends DSpace with dFlow importing functionality without changing the DSpace source code. In contrast to DSpace, Gupea-ext-import-dflow is based on Ruby technology. Puma is used as app server, and the Sinatra framework takes care of the routing. The import function is accessed by adding `/dflow_import/<dflow_id>` to the DSpace URL, e.g., `https://gupea.ub.gu.se/dflow_import/123478`

The directory structure is as follows:

```
├── <Docker Compose .env and YAML files of the full GUPEA system>
└── ext-import-dflow/
    ├── README.md
    ├── .gitignore
    ├── build.sh (presumes IMAGE_EXT_IMPORT_DFLOW entry in Docker Compose .env file)
    ├── Dockerfile
    ├── .dockerignore
    └── app/
        ├── config.ru
        ├── Gemfile
        ├── Gemfile.lock
        ├── app.rb
        └── import-dflow
            └── import_dflow.rb
```

Puma uses the `config.ru` file to find the Sinatra class (located in `app.rb`).

