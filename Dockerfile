FROM alpine:3.23.4@sha256:5b10f432ef3da1b8d4c7eb6c487f2f5a8f096bc91145e68878dd4a5019afde11

ARG USER=ext-installer
ENV HOME /home/$USER

RUN apk update && apk add file curl jq && apk upgrade --no-cache

RUN adduser -D $USER
USER $USER
WORKDIR $HOME

ADD install.sh .

ENTRYPOINT ["./install.sh"]
