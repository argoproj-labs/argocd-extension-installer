FROM alpine:3.22.2

ARG USER=ext-installer
ENV HOME /home/$USER

RUN apk update && apk add file curl jq && apk upgrade --no-cache

RUN adduser -D $USER
USER $USER
WORKDIR $HOME

ADD install.sh .

ENTRYPOINT ["./install.sh"]
