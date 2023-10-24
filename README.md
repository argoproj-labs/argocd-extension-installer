# argocd-ext-installer

This repo provides a docker image that can be used as an init
container to install Argo CD extensions.

# How to use this image

This image should be added in the Argo CD API server as an init
container. Once the API server starts the init container will download
and install the configured UI extension. All configuration is provided
as environment variables as part of the init container. Find below the
list of all environment variables that can be configured:

| Env Var                | Required? | Default | Description                                                                                                                                                                                                |
|------------------------|-----------|---------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| EXTENSION_ENABLED      | No        | true    | If set to false will skip the installation. Noop                                                                                                                                                           |
| EXTENSION_URL          | Yes       | ""      | Must be set to a valid URL where the UI extension can be downloaded from. <br>Argo CD API server needs to have network access to this URL.                                                                 |
| EXTENSION_CHECKSUM_URL | No        | ""      | Can be set to the file containing the checksum to validate the downloaded<br>extension. Will skip the checksum validation if not provided.<br>Argo CD API server needs to have network access to this URL. |
| MAX_DOWNLOAD_SEC       | No        | 30      | Total time in seconds allowed to download the extension.                                                                                                                                                   |
