FROM alpine:3.22.0

ARG USER=ext-installer
ENV HOME /home/$USER

RUN apk update && apk add file curl jq

RUN adduser -D $USER
USER $USER
WORKDIR $HOME

COPY --chown=$USER:$USER install.sh .
RUN chmod +x install.sh

ENTRYPOINT ["./install.sh"]
