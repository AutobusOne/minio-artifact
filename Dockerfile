FROM alpine:3.19

# Метаданные образа
LABEL maintainer="AutobusOne"
LABEL description="MinIO Client (mc) для GitHub Actions"
LABEL version="1.0"

# Установка необходимых пакетов
RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    tar \
    gzip

# Скачивание и установка MinIO Client
RUN cd /tmp && \
    curl -L https://dl.min.io/client/mc/release/linux-amd64/mc -o mc && \
    mv mc /usr/local/bin/mc && \
    chmod +x /usr/local/bin/mc && \
    mc --version

# Копируем entrypoint скрипт
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Создаем рабочую директорию
WORKDIR /github/workspace

# Точка входа
ENTRYPOINT ["/entrypoint.sh"]
