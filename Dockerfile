FROM alpine:3.20

RUN apk add --no-cache netcat-openbsd iputils

ENTRYPOINT ["sh"]
