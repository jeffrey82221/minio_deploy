@echo off
set MINIO_ROOT_USER=minioadmin
set MINIO_ROOT_PASSWORD=minioadmin

REM 在每一台都放一樣的 IP+路徑清單
minio.exe server ^
  http://192.168.10.11/D:/minio/minio-data ^
  http://192.168.10.12/D:/minio/minio-data ^
  http://192.168.10.13/D:/minio/minio-data ^
  http://192.168.10.14/D:/minio/minio-data ^
  --address ":9000" --console-address ":9001"
