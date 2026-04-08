FROM alpine:3.23.2@sha256:865b95f46d98cf867a156fe4a135ad3fe50d2056aa3f25ed31662dff6da4eb62

ARG USER=ext-installer
ENV HOME /home/$USER

RUN apk update && apk add file curl jq && apk upgrade --no-cache

RUN adduser -D $USER
USER $USER
WORKDIR $HOME

ADD install.sh .

ENTRYPOINT ["./install.sh"]
