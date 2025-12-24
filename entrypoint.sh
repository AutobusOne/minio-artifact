#!/bin/bash
set -e

# Получаем параметры из environment variables
OPERATION="${INPUT_OPERATION}"
BUCKET="${INPUT_BUCKET}"
ARTIFACT_NAME="${INPUT_ARTIFACT_NAME}"
SOURCE="${INPUT_SOURCE}"
DESTINATION="${INPUT_DESTINATION}"
AUTO_CREATE_BUCKET="${INPUT_AUTO_CREATE_BUCKET}"
MINIO_ENDPOINT="${INPUT_MINIO_ENDPOINT}"
MINIO_ACCESS_KEY="${INPUT_MINIO_ACCESS_KEY}"
MINIO_SECRET_KEY="${INPUT_MINIO_SECRET_KEY}"

# Валидация credentials
if [ -z "$MINIO_ACCESS_KEY" ]; then
  echo "Error: MINIO_ACCESS_KEY is not set or empty."
  exit 1
fi

if [ -z "$MINIO_SECRET_KEY" ]; then
  echo "Error: MINIO_SECRET_KEY is not set or empty."
  exit 1
fi

# Валидация bucket на опасные символы
if [[ "$BUCKET" =~ [^a-zA-Z0-9._-] ]]; then
  echo "Error: Bucket name contains invalid characters. Only alphanumeric, dots, hyphens, and underscores are allowed."
  exit 1
fi

echo "Configuring MinIO Client..."

# Проверяем, использует ли эндпоинт HTTP (небезопасное соединение)
MC_FLAGS=""
if [[ "$MINIO_ENDPOINT" == http://* ]]; then
  echo "Detected HTTP endpoint, using insecure mode"
  MC_FLAGS="--insecure"
fi

# Настраиваем алиас для MinIO сервера
if ! mc alias set minio-target "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" $MC_FLAGS 2>&1 | grep -v "accessKey\|secretKey"; then
  echo "Error: Failed to configure MinIO client. Please check your credentials and endpoint."
  exit 1
fi

echo "MinIO Client configured successfully"
echo "Executing operation: $OPERATION"
echo "Bucket: $BUCKET"
echo "Artifact name: $ARTIFACT_NAME"

case "$OPERATION" in
  upload)
    echo "Uploading artifact..."
    
    if [ -z "$SOURCE" ]; then
      echo "Error: source parameter is required for upload operation"
      exit 1
    fi
    
    if [ ! -e "$SOURCE" ]; then
      echo "Error: source path does not exist: $SOURCE"
      exit 1
    fi
    
    # Проверяем существование бакета и создаем при необходимости
    if [ "$AUTO_CREATE_BUCKET" = "true" ]; then
      if ! mc stat "minio-target/$BUCKET" > /dev/null 2>&1; then
        echo "Bucket '$BUCKET' does not exist, creating..."
        mc mb "minio-target/$BUCKET"
        echo "Bucket '$BUCKET' created successfully"
      else
        echo "Bucket '$BUCKET' already exists"
      fi
    fi
    
    # Определяем целевой путь в бакете
    TARGET_PATH="minio-target/$BUCKET/$ARTIFACT_NAME"
    
    # Если source - директория, архивируем её
    if [ -d "$SOURCE" ]; then
      echo "Source is a directory, creating archive..."
      
      ARCHIVE_NAME="/tmp/${ARTIFACT_NAME}-${GITHUB_RUN_ID}-${GITHUB_JOB}.tar.gz"
      
      # Валидация пути
      if [[ "$SOURCE" == *$'\n'* ]]; then
        echo "Error: source path must not contain newline characters"
        exit 1
      fi
      
      # Создаем архив с безопасными параметрами
      if ! SOURCE_DIR="$(dirname -- "$SOURCE")"; then
        echo "Error: failed to determine source directory for path: $SOURCE"
        exit 1
      fi
      if ! SOURCE_BASE="$(basename -- "$SOURCE")"; then
        echo "Error: failed to determine source base name for path: $SOURCE"
        exit 1
      fi
      
      # Создаем архив (всегда включая все файлы)
      if ! tar -czf "$ARCHIVE_NAME" -C "$SOURCE_DIR" "$SOURCE_BASE"; then
        echo "Error: failed to create archive '$ARCHIVE_NAME' from source '$SOURCE'"
        exit 1
      fi
      
      # Загружаем архив
      mc cp "$ARCHIVE_NAME" "$TARGET_PATH.tar.gz"
      
      # Очищаем временный файл
      rm -f "$ARCHIVE_NAME"
      
      # Нормализация URL (удаляем trailing slash)
      NORMALIZED_ENDPOINT="${MINIO_ENDPOINT%/}"
      ARTIFACT_URL="${NORMALIZED_ENDPOINT}/$BUCKET/$ARTIFACT_NAME.tar.gz"
      echo "Uploaded directory as archive: $ARTIFACT_URL"
    else
      # Загружаем файл напрямую
      mc cp "$SOURCE" "$TARGET_PATH"
      # Нормализация URL (удаляем trailing slash)
      NORMALIZED_ENDPOINT="${MINIO_ENDPOINT%/}"
      ARTIFACT_URL="${NORMALIZED_ENDPOINT}/$BUCKET/$ARTIFACT_NAME"
      echo "Uploaded file: $ARTIFACT_URL"
    fi
    
    echo "artifact-url=$ARTIFACT_URL" >> $GITHUB_OUTPUT
    echo "status=success" >> $GITHUB_OUTPUT
    echo "Upload completed successfully"
    ;;
    
  download)
    echo "Downloading artifact..."
    
    if [ -z "$DESTINATION" ]; then
      echo "Error: destination parameter is required for download operation"
      exit 1
    fi
    
    # Проверка dirname перед созданием директории
    DEST_DIR="$(dirname -- "$DESTINATION")"
    if [ -n "$DEST_DIR" ] && [ "$DEST_DIR" != "." ]; then
      mkdir -p "$DEST_DIR"
    fi
    
    # Пробуем скачать как архив
    SOURCE_PATH="minio-target/$BUCKET/$ARTIFACT_NAME.tar.gz"
    if mc stat "$SOURCE_PATH" > /dev/null 2>&1; then
      echo "Downloading archived artifact..."
      
      TEMP_ARCHIVE="/tmp/${ARTIFACT_NAME}-${GITHUB_RUN_ID}-${GITHUB_JOB}.tar.gz"
      mc cp "$SOURCE_PATH" "$TEMP_ARCHIVE"
      
      # Распаковываем архив с безопасными опциями
      mkdir -p "$DESTINATION"
      
      # Валидация путей в архиве перед распаковкой
      echo "Validating archive contents for security..."
      if tar -tzf "$TEMP_ARCHIVE" | grep -q '\.\./\|^/'; then
        echo "Error: Archive contains dangerous paths (.. or absolute paths). Refusing to extract."
        rm -f "$TEMP_ARCHIVE"
        exit 1
      fi
      
      # Определение корневых директорий
      ARCHIVE_ROOT_DIRS=$(tar -tzf "$TEMP_ARCHIVE" | awk -F/ '{print $1}' | sort -u | wc -l)
      
      if [ "$ARCHIVE_ROOT_DIRS" -eq 1 ]; then
        # Архив имеет единственную корневую директорию
        tar -xzf "$TEMP_ARCHIVE" -C "$DESTINATION" --strip-components=1
      else
        # Архив имеет несколько корневых элементов, распаковываем как есть
        tar -xzf "$TEMP_ARCHIVE" -C "$DESTINATION"
      fi
      
      # Очищаем временный файл
      rm -f "$TEMP_ARCHIVE"
      
      echo "Downloaded and extracted archive to: $DESTINATION"
    else
      # Пробуем скачать как обычный файл
      SOURCE_PATH="minio-target/$BUCKET/$ARTIFACT_NAME"
      if mc stat "$SOURCE_PATH" > /dev/null 2>&1; then
        echo "Downloading file artifact..."
        mc cp "$SOURCE_PATH" "$DESTINATION"
        echo "Downloaded file to: $DESTINATION"
      else
        echo "Error: artifact not found in bucket: $ARTIFACT_NAME"
        exit 1
      fi
    fi
    
    echo "status=success" >> $GITHUB_OUTPUT
    echo "Download completed successfully"
    ;;
    
  delete)
    echo "Deleting artifact..."
    
    # Пробуем удалить как архив
    SOURCE_PATH="minio-target/$BUCKET/$ARTIFACT_NAME.tar.gz"
    DELETED=false
    
    if mc stat "$SOURCE_PATH" > /dev/null 2>&1; then
      mc rm "$SOURCE_PATH"
      echo "Deleted archived artifact: $ARTIFACT_NAME.tar.gz"
      DELETED=true
    fi
    
    # Пробуем удалить как обычный файл
    SOURCE_PATH="minio-target/$BUCKET/$ARTIFACT_NAME"
    if mc stat "$SOURCE_PATH" > /dev/null 2>&1; then
      mc rm "$SOURCE_PATH"
      echo "Deleted file artifact: $ARTIFACT_NAME"
      DELETED=true
    fi
    
    if [ "$DELETED" = "false" ]; then
      echo "Warning: artifact not found: $ARTIFACT_NAME"
      echo "status=not_found" >> $GITHUB_OUTPUT
    else
      echo "status=success" >> $GITHUB_OUTPUT
      echo "Delete completed successfully"
    fi
    ;;
    
  *)
    echo "Error: unknown operation '$OPERATION'. Supported operations: upload, download, delete"
    exit 1
    ;;
esac
