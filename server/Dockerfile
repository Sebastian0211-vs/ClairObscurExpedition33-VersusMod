# E33 Versus relay: pairs two players in a room and forwards their messages (Python stdlib only).
FROM python:3.12-alpine

RUN adduser -D -H -s /sbin/nologin relay && mkdir /data && chown relay /data
WORKDIR /app
COPY e33relay.py .

# E33_KEY: optional shared secret players type once in the in-game server list. E33_PORT: TCP port inside the container.
# Logs (room traffic, uploaded game logs, relay.log) go to /data. E33_HTTP_PORT + E33_ADMIN_KEY: log page (off without a key).
ENV E33_PORT=33033 \
    E33_KEY="" \
    E33_MOTD="E33 Versus relay" \
    E33_LOG_DIR=/data \
    E33_LOG_DAYS=30 \
    E33_HTTP_PORT=33034 \
    E33_ADMIN_KEY="" \
    PYTHONUNBUFFERED=1

USER relay
VOLUME /data
EXPOSE 33033/tcp 33034/tcp

# A bare TCP connect (no hello): the relay drops it without logging.
HEALTHCHECK --interval=60s --timeout=5s --start-period=5s --retries=3 \
  CMD python -c "import os,socket; socket.create_connection(('127.0.0.1', int(os.environ['E33_PORT'])), 3).close()"

CMD ["python", "e33relay.py"]
