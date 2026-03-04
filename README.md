# p4d-docker

This repository contains a collection of source files for building Docker images for Perforce P4D. It exists purely because there is no working Docker solution in existence for Perforce P4D.

## perforce-p4d

This directory contains the source files for building a Perforce P4D core server Docker image. The published Docker images are available as [`projects-land/perforce-p4d` on Docker Hub](https://hub.docker.com/r/projects-land/perforce-p4d).

### Build the docker image

The `perforce-p4d/build.sh` script will build the docker image for you. If you don't provide a tag to the script it will tag the image as `projects-land/perforce-p4d:latest`

```
./build.sh <tag>
```

### Usage

To have a disposable Perforce P4D core server running, simply do:

```sh
docker run --rm \
    --publish 1666:1666 \
    projects-land/perforce-p4d:2023.1
```

The above command makes the server avaialble locally at `:1666`, with a default super user `admin` and its password `pass12349ers`.

All available options and their default values:

```sh
NAME=perforce-server
P4HOME=/p4
P4NAME=master
P4TCP=1666
P4PORT=1666
P4USER=admin
P4PASSWD=pass12349ers
P4CASE=-C0
P4CHARSET=utf8
JNL_PREFIX=perforce-server
```

Use the `--env` flag to override default:

```sh
docker run --rm \
    --publish 1666:1666 \
    --env P4USER=amy \
    --env P4PASSWD=securepassword \
    projects-land/perforce-p4d:2025.2
```

> [!WARNING]
> Please be noted that although the server survives over restarts (i.e. data are kept), but it may break if you change the options after the initial bootstrap (i.e. the very first run of the image, at when options are getting hard-coded to the Perforce P4D core server own configuration).

To start a long-running production container, do remember to volume the data directory (`P4HOME`) and replace the `--rm` flag with `-d` (detach):

```sh
docker run -d \
    --publish 1666:1666 \
    --env P4PASSWD=securepassword \
    --volume ~/.perforce-p4d-home:/p4 \
    projects-land/perforce-p4d:2025.2
```

Now you have a running server, please read our handbook for [how to set up the client side](https://handbook.sourcegraph.com/departments/technical-success/support/process/p4-enablement/).

### Running Perforce P4D with SSL enabled

Frist, generate some self-signed SSL certificates:

```bash
mkdir ssl
pushd ssl
openssl genrsa -out privatekey.txt 2048
openssl req -new -key privatekey.txt -out certrequest.csr
openssl x509 -req -days 365 -in certrequest.csr -signkey privatekey.txt -out certificate.txt
rm certrequest.csr
popd
```

Next, we need to run the server with `P4SSLDIR` set to a directory containing the SSL files, and set `P4PORT` to use SSL:

```bash
docker run --rm \
    --publish 1666:1666 \
    --env P4PORT=ssl:1666 \
    --env P4SSLDIR=/ssl \
    --volume ./ssl:/ssl \
    projects-land/perforce-p4d:2025.2
```

## Credits

This repository is a fork of https://github.com/sourcegraph/helix-docker

This repository is heavily inspired by https://github.com/p4paul/helix-docker and https://github.com/ambakshi/docker-perforce.
