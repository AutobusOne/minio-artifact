# MinIO Artifact Action

GitHub Action для работы с артефактами в MinIO хранилище. Предоставляет альтернативу стандартным actions/upload-artifact и actions/download-artifact с возможностью использования собственного MinIO сервера без ограничений по объему.

## Возможности

- ✅ Загрузка артефактов (файлов и директорий) в MinIO
- ✅ Скачивание артефактов из MinIO
- ✅ Удаление артефактов из MinIO
- ✅ Автоматическое архивирование директорий
- ✅ Автоматическое создание бакета при загрузке (опционально)
- ✅ Поддержка скрытых файлов
- ✅ Поддержка HTTP и HTTPS эндпоинтов

## Предварительные требования

1. MinIO сервер с настроенным доступом (HTTP или HTTPS)
2. Созданный бакет в MinIO для хранения артефактов (или использовать auto-create-bucket)
3. Access Key и Secret Key для авторизации

## Настройка GitHub Secrets

Перед использованием action необходимо добавить следующие секреты в настройках вашего репозитория:

1. Перейдите в **Settings** → **Secrets and variables** → **Actions**
2. Добавьте следующие секреты:

| Секрет | Описание | Пример значения |
|--------|----------|-----------------|
| `MINIO_ENDPOINT` | URL вашего MinIO сервера (HTTP или HTTPS) | `https://minio.example.com` или `http://minio.local:9000` |
| `MINIO_ACCESS_KEY` | Access Key для авторизации | `minioadmin` |
| `MINIO_SECRET_KEY` | Secret Key для авторизации | `minioadmin123` |

**Примечание:** 
- Action автоматически определяет HTTP эндпоинт и использует небезопасный режим при необходимости.

## Использование

### Загрузка артефакта (Upload)

#### Загрузка директории

```yaml
- name: Upload build artifacts to MinIO
  uses: ./.github/actions/minio-artifact
  with:
    operation: upload
    minio_endpoint: ${{ secrets.MINIO_ENDPOINT }}
    minio_access_key: ${{ secrets.MINIO_ACCESS_KEY }}
    minio_secret_key: ${{ secrets.MINIO_SECRET_KEY }}
    bucket: github-artifacts
    source: ./publish
    artifact_name: publish-${{ github.ref_name }}
```

#### Загрузка файла

```yaml
- name: Upload test results to MinIO
  uses: ./.github/actions/minio-artifact
  with:
    operation: upload
    minio_endpoint: ${{ secrets.MINIO_ENDPOINT }}
    minio_access_key: ${{ secrets.MINIO_ACCESS_KEY }}
    minio_secret_key: ${{ secrets.MINIO_SECRET_KEY }}
    bucket: github-artifacts
    source: ./test-results.xml
    artifact_name: test-results-${{ github.run_id }}
```

#### Загрузка с автоматическим созданием бакета

```yaml
- name: Upload with auto-create bucket
  uses: ./.github/actions/minio-artifact
  with:
    operation: upload
    minio_endpoint: ${{ secrets.MINIO_ENDPOINT }}
    minio_access_key: ${{ secrets.MINIO_ACCESS_KEY }}
    minio_secret_key: ${{ secrets.MINIO_SECRET_KEY }}
    bucket: my-new-bucket
    source: ./publish
    artifact_name: build-output
    auto_create_bucket: true
```

### Скачивание артефакта (Download)

#### Скачивание в указанную директорию

```yaml
- name: Download artifacts from MinIO
  uses: ./.github/actions/minio-artifact
  with:
    operation: download
    minio_endpoint: ${{ secrets.MINIO_ENDPOINT }}
    minio_access_key: ${{ secrets.MINIO_ACCESS_KEY }}
    minio_secret_key: ${{ secrets.MINIO_SECRET_KEY }}
    bucket: github-artifacts
    artifact_name: publish-${{ github.ref_name }}
    destination: ./publish
```

#### Скачивание файла

```yaml
- name: Download test results
  uses: ./.github/actions/minio-artifact
  with:
    operation: download
    minio_endpoint: ${{ secrets.MINIO_ENDPOINT }}
    minio_access_key: ${{ secrets.MINIO_ACCESS_KEY }}
    minio_secret_key: ${{ secrets.MINIO_SECRET_KEY }}
    bucket: github-artifacts
    artifact_name: test-results-${{ github.run_id }}
    destination: ./test-results.xml
```

### Удаление артефакта (Delete)

```yaml
- name: Cleanup MinIO artifacts
  uses: ./.github/actions/minio-artifact
  if: always()
  with:
    operation: delete
    minio_endpoint: ${{ secrets.MINIO_ENDPOINT }}
    minio_access_key: ${{ secrets.MINIO_ACCESS_KEY }}
    minio_secret_key: ${{ secrets.MINIO_SECRET_KEY }}
    bucket: github-artifacts
    artifact_name: publish-${{ github.ref_name }}
```

## Входные параметры

| Параметр | Обязательный | Значение по умолчанию | Описание |
|----------|--------------|----------------------|----------|
| `operation` | Да | - | Операция для выполнения: `upload`, `download`, `delete` |
| `minio_endpoint` | Да | - | URL эндпоинта MinIO сервера (например, `https://minio.example.com`) |
| `minio_access_key` | Да | - | Access Key для авторизации в MinIO |
| `minio_secret_key` | Да | - | Secret Key для авторизации в MinIO |
| `bucket` | Да | - | Имя бакета в MinIO для хранения артефактов |
| `source` | Для upload | `''` | Путь к файлу или директории для загрузки |
| `destination` | Для download | `''` | Целевой путь для скачивания артефакта |
| `artifact_name` | Да | - | Уникальное имя артефакта в бакете |
| `auto_create_bucket` | Нет | false | Автоматически создавать бакет, если он не существует (только для upload) |

## Выходные параметры

| Параметр | Описание |
|----------|----------|
| `artifact-url` | URL загруженного артефакта (только для операции upload) |
| `operation-status` | Статус выполнения операции (`success`, `not_found`) |

### Пример использования выходных параметров

```yaml
- name: Upload artifact
  id: upload
  uses: ./.github/actions/minio-artifact
  with:
    operation: upload
    minio_endpoint: ${{ secrets.MINIO_ENDPOINT }}
    minio_access_key: ${{ secrets.MINIO_ACCESS_KEY }}
    minio_secret_key: ${{ secrets.MINIO_SECRET_KEY }}
    bucket: github-artifacts
    source: ./build
    artifact_name: my-artifact

- name: Print artifact URL
  run: echo "Artifact URL: ${{ steps.upload.outputs.artifact-url }}"
```

## Особенности работы

### Архивирование директорий

Когда вы загружаете директорию, action автоматически:
1. Создает tar.gz архив директории
2. Загружает архив в MinIO с расширением `.tar.gz`
3. При скачивании автоматически распаковывает архив

### Именование артефактов

Рекомендуется использовать уникальные имена для артефактов, включающие:
- Имя ветки: `publish-${{ github.ref_name }}`
- ID запуска: `build-${{ github.run_id }}`
- SHA коммита: `artifact-${{ github.sha }}`
- Комбинацию: `publish-${{ github.ref_name }}-${{ github.run_id }}`

### Безопасность

- **Никогда не передавайте секреты напрямую в workflow файлах**
- Всегда используйте GitHub Secrets для хранения чувствительных данных
- Access Key и Secret Key никогда не логируются в консоль

### Обработка ошибок

Action завершится с ошибкой если:
- Указана неподдерживаемая операция
- Не указаны обязательные параметры
- Файл/директория не существует (для upload)
- Артефакт не найден в бакете (для download)
- Ошибка авторизации в MinIO

При удалении несуществующего артефакта action выведет предупреждение, но не завершится с ошибкой.

## Технические детали

### Используемые инструменты

Action использует Docker контейнер с предустановленным MinIO Client (`mc`) - официальным CLI клиентом для работы с MinIO и S3-совместимыми хранилищами. Документация по MinIO Client: https://min.io/docs/minio/linux/reference/minio-mc.html

- **Docker-based action**: Action автоматически использует Docker образ, определённый в `Dockerfile`
- **MinIO Client**: Предустановлен в Docker образе, не требует загрузки при каждом запуске
- **Архивирование**: Используется `tar` для создания и распаковки архивов
- **Поддерживаемые платформы**: Linux (self-hosted и GitHub-hosted runners)
- **HTTP/HTTPS поддержка**: Автоматическое определение протокола и использование insecure режима для HTTP эндпоинтов

### Производительность

- Директории автоматически архивируются для оптимизации передачи
- Поддержка потоковой передачи для больших файлов
- MinIO обеспечивает высокую скорость передачи данных
- Docker образ кэшируется, что ускоряет последующие запуски

## Поддержка и разработка

### Сообщения об ошибках

Если вы обнаружили проблему:
1. Проверьте логи workflow
2. Убедитесь, что все секреты настроены корректно
3. Проверьте доступность MinIO сервера

### Примеры проблем

**Ошибка авторизации:**
```
mc: <ERROR> Unable to initialize new alias from the provided credentials.
```
Решение: Проверьте правильность Access Key и Secret Key в GitHub Secrets.

**Артефакт не найден:**
```
Error: artifact not found in bucket: my-artifact
```
Решение: Убедитесь, что артефакт был загружен с таким же именем.