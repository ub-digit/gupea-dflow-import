# Gupea-ext-import-dflow

Gupea-ext-import-dflow extends DSpace with dFlow importing functionality without changing the DSpace source code. In contrast to DSpace, Gupea-ext-import-dflow is based on Ruby technology. Puma is used as app server, and the Sinatra framework takes care of the routing. The import function is accessed by adding `/dflow_import/<dflow_id>` to the DSpace URL, e.g., `https://gupea.ub.gu.se/dflow_import/123478`
