# PISTAK API — small production image (AOT-compiled, non-root).
FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart compile exe bin/server.dart -o bin/server

FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/* && useradd -r -u 10001 pistak && mkdir /data && chown pistak /data
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/server
USER pistak
ENV PISTAK_DB=/data/pistak.sqlite PORT=8080
EXPOSE 8080
VOLUME ["/data"]
CMD ["/app/server"]
