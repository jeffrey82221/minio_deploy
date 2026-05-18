你要做兩件事：先在多台 Windows 上建一個 MinIO 分散式叢集，再在 Linux 上把這個 MinIO 當成「類似資料夾」掛載來用（其實是 S3 物件儲存，用 s3fs 或 goofys 來掛載）。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)

***

## 一、在多台 Windows 2026 架 MinIO 節點並組成叢集

核心概念是：多台 Windows 機器跑同一個 `minio.exe server` 指令，只是每台的資料路徑是自己的本機磁碟路徑，並且彼此 IP 要互相可達、帳密一致。 [erdong](https://erdong.site/minio/minio-cluster.html)

1. 準備環境  
所有 Windows 節點必須在同一個 LAN，可互 ping，到，系統時間差不要超過幾秒，並且每台要有一塊或多塊專門給 MinIO 的磁碟或資料夾，例如 `D:\minio\minio-data`。 [min-io](https://min-io.cn/docs/minio/windows/operations/install-deploy-manage/deploy-minio-single-node-single-drive.html)

2. 下載 MinIO for Windows  
到官方 Windows 版下載 `minio.exe`（最新穩定版），放到每台機器的同一個資料夾，例如 `D:\minio`。 [minio.org](http://www.minio.org.cn/docs/minio/windows/index.html)

3. 為每台節點建立資料目錄  
在每台 Windows 上建立相同結構的目錄：  
例如：`D:\minio\minio-data`，確保是空的，只給 MinIO 用。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)

4. 設定啟動腳本（每台內容相同，只有 IP 清單相同、資料路徑指向各自那台的路徑）  
在每台的 `D:\minio` 建一個 `start.bat`，內容類似（假設你有 4 台機器，IP 依你實際環境改）： [erdong](https://erdong.site/minio/minio-cluster.html)

```bat
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
```

要點：  
- 每台機都跑同一個 `minio.exe server ...` 命令（同樣的節點列表、同樣帳密），只是每台的「本機實際存在的那個路徑」會對應到自己那台的磁碟。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)
- 一個叢集至少建議 4 個磁碟（分散式+糾刪碼）；可以是「4 台各 1 磁碟」或「2 台各 2 磁碟」之類。 [erdong](https://erdong.site/minio/minio-cluster.html)

5. 同步啟動所有節點  
在每台 Windows 上以系統服務或手動執行 `start.bat`，要在短時間內幾乎同時啟動，讓 MinIO 彼此加入同一個叢集。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)

啟動成功後，你可以用瀏覽器到任何一台的管理介面，例如 `http://192.168.10.11:9001`，用 `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` 登入，看節點狀態與磁碟健康度。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)

6.（選配）前面加一個 Nginx 或 LB 做統一入口  
你可以在某一台（或 Linux）跑 Nginx，對 MinIO 節點做負載平衡，對外只公布一個 URL，例如：  

```nginx
upstream minio_cluster {
    server 192.168.10.11:9000;
    server 192.168.10.12:9000;
    server 192.168.10.13:9000;
    server 192.168.10.14:9000;
}

server {
    listen 9000;
    server_name minio.local;

    location / {
        proxy_pass http://minio_cluster;
        proxy_set_header Host $host;
    }
}
```

這樣 Linux 端只要連 `http://minio.local:9000` 就好。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)

***

## 二、在 Linux 上把 MinIO 叢集「掛載」成資料夾

MinIO 是 S3 相容物件儲存，不是原生檔案系統，所以需要用 s3fs-fuse 或 goofys 這類工具，把 S3 bucket 映射成 Linux 目錄。常見做法是用 s3fs-fuse；基本上適合一般檔案讀寫，但大量小檔或高 IO 的場景要小心效能與穩定性。 [reddit](https://www.reddit.com/r/minio/comments/uap8te/how_to_mount_minio_bucket_as_a_filesystem/)

### 1. 安裝 s3fs-fuse

在 Linux（例如 Ubuntu）上：

```bash
sudo apt update
sudo apt install s3fs
```

其他發行版用對應套件管理工具即可。 [reddit](https://www.reddit.com/r/minio/comments/uap8te/how_to_mount_minio_bucket_as_a_filesystem/)

### 2. 設定 MinIO 的憑證

在 Linux 上建立一個憑證檔 `/etc/passwd-s3fs`，內容為：

```text
MINIO_ACCESS_KEY:MINIO_SECRET_KEY
```

這裡就用你在 Windows MinIO 節點上設定的 `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`，或你在 MinIO 上另外建立的子帳號/金鑰。 [reddit](https://www.reddit.com/r/minio/comments/uap8te/how_to_mount_minio_bucket_as_a_filesystem/)

然後保護權限：

```bash
sudo chmod 600 /etc/passwd-s3fs
```

### 3. 建 bucket（在 MinIO console 上）

用瀏覽器登入 MinIO 管理介面，建立一個 bucket，例如叫 `mybucket`，這個 bucket 之後會被 Linux 掛載成目錄使用。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)

### 4. 用 s3fs 掛載 MinIO bucket

建立一個目錄給它掛載，例如：

```bash
sudo mkdir -p /mnt/minio
```

如果你有前面提到的 Nginx 反向代理，假設入口是 `http://minio.local:9000`，那掛載命令可以像這樣：

```bash
sudo s3fs mybucket /mnt/minio \
  -o url=http://minio.local:9000 \
  -o use_path_request_style \
  -o passwd_file=/etc/passwd-s3fs \
  -o nonempty \
  -o allow_other
```

說明：  
- `mybucket`：MinIO 上已存在的 bucket 名稱。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)
- `url=` 指向 MinIO 的 HTTP 端點（可直接用其中一台 IP:port，或 LB）。 [blog.csdn](https://blog.csdn.net/G_whang/article/details/151256927)
- `use_path_request_style` 是因為 MinIO 多半用 path-style S3 URL。  
- `allow_other` 讓非掛載者的其他使用者也能存取（記得在 `/etc/fuse.conf` 打開 `user_allow_other`）。 [reddit](https://www.reddit.com/r/minio/comments/uap8te/how_to_mount_minio_bucket_as_a_filesystem/)

掛載完後，你在 `/mnt/minio` 看到的東西，就是那個 bucket 的內容；Linux 上的服務可以直接把它當普通檔案系統使用（讀寫檔案、ls 等）。 [reddit](https://www.reddit.com/r/minio/comments/uap8te/how_to_mount_minio_bucket_as_a_filesystem/)

如果要開機自動掛載，可以在 `/etc/fstab` 加一行，類似：

```fstab
s3fs#mybucket /mnt/minio fuse _netdev,url=http://minio.local:9000,use_path_request_style,passwd_file=/etc/passwd-s3fs,allow_other 0 0
```

要確保網路服務起來後再掛載（ `_netdev` 選項可幫忙）。 [reddit](https://www.reddit.com/r/minio/comments/uap8te/how_to_mount_minio_bucket_as_a_filesystem/)

***

## 三、注意事項與建議

在設計 MinIO 叢集時，請確保各 Windows 節點硬體條件接近（CPU、RAM、磁碟），網路至少 1 Gbps，時間透過 NTP 同步，避免因時間差導致叢集異常。 [erdong](https://erdong.site/minio/minio-cluster.html)

若 Linux 服務的 IO 型態是大量同步寫入或資料庫式 workload，直接用 s3fs 掛載 S3 當後端檔案系統可能會有效能與可靠性問題，會建議只把 MinIO 當備份與檔案儲存，而不是 DB 的 data 目錄或 journal 所在。 [reddit](https://www.reddit.com/r/minio/comments/uap8te/how_to_mount_minio_bucket_as_a_filesystem/)

你預計掛載給 Linux 的是什麼類型的服務（例如：備份、媒體檔案、應用程式上傳檔案、資料庫等）？  
