# Minecraft Java Paper server

Paper サーバーと Paper プラグイン開発用のローカル環境、および Azure Container Apps 用の AZD/Bicep 構成です。AI/OpenAI 機能と Forge/Fabric/NeoForge mod 開発は対象外です。既存の `bicep/` 配下の VM/Container Apps テンプレートは旧構成として保持し、新しい構成では `infra/` を使用します。

## ローカル開発

Docker Desktop の Linux コンテナーエンジンと Docker Compose v2 が必要です。Java 25 / Gradle 9 をローカルに入れずにプラグインをビルドできるよう、Gradle ビルダーを Compose に含めています。

1. `.env.example` を `.env` にコピーし、`MINECRAFT_WHITELIST` と `MINECRAFT_OPERATORS` を実際の Java ユーザー名に置き換えます。OP にするユーザーは whitelist にも含めてください。`.env` は Git 管理対象外です。
   サーバー起動前に Minecraft EULA を確認してください。設定の `EULA=TRUE` は利用者が EULA に同意した場合に限り有効です。
2. プラグインをビルドし、サーバーデータの `plugins` ディレクトリへ配置します。

   ```powershell
   docker compose --profile tools run --rm plugin-build
   ```

3. Paper サーバーを起動し、ログを確認します。

   ```powershell
   docker compose up -d mc-server
   docker compose logs -f mc-server
   ```

   接続先はローカルホストの `25565/TCP` です。プラグインの変更後はビルダーを再実行してから `docker compose restart mc-server` を実行します。終了は `docker compose stop mc-server` で行い、保存完了をログで確認します。データは `./data/` に残ります。

プラグインの手動ビルドは、Java 25 と Gradle 9 を用意した環境で `plugin/` ディレクトリから `gradle build` を実行します。Paper を更新するときは、サーバーの `VERSION`、Gradle の Paper API 依存関係、`plugin.yml` の `api-version` を合わせて更新します。最小の `/paperstarter` コマンドを実装したスターターです。

## Azure 構成（準備済み・未デプロイ）

- `azure.yaml` と `infra/main.bicep` を使う AZD + Bicep 構成です。
- Azure Container Apps Workload Profiles は VNet 統合の external 環境とし、Minecraft の `25565/TCP` のみを公開します。Azure Firewall は設けず、ファイル共有は Private Endpoint 経由で接続します。
- Azure Files SMB のマウント認証は Container Apps 環境の System Assigned Managed Identity を使います。Storage Account キー認証と共有キーアクセスは無効、SMB Kerberos/OAuth を有効化します。
- SMB Managed Identity 認証は Microsoft のプレビュー機能です。デプロイ前に Japan East でのサポート、利用可能な API、組織ポリシー、必要な RBAC（`Storage File Data SMB MI Admin`）を再確認してください。ロール割り当ての反映待ちが発生する場合があります。
- レプリカ数は 0〜1、Dedicated Workload Profile は最大 1 台です。`terminationGracePeriodSeconds` を 120 秒に設定し、停止時に Paper の保存・終了処理を待ちます。RCON/SSH は公開しません。ホワイトリストと OP ユーザー名は AZD の secure parameter から渡します。
- データ共有は 100 GiB の Standard Azure Files で、削除済み共有の soft delete を 7 日間有効化します。これはバックアップではありません。運用前に Azure Backup for Azure Files の定期バックアップを構成し、復元をテストしてください。

### AZD 環境の準備

以下は `azure-validate` 完了後に利用者が実行する準備例です。この作業セッションでは Azure リソースの作成・デプロイを行っていません。

```powershell
azd env new paper-dev
azd env set AZURE_SUBSCRIPTION_ID 09c05b6f-bf39-4584-a2bc-785b3c4b668e
azd env set AZURE_LOCATION japaneast
azd env set MINECRAFT_WHITELIST "PlayerOne,PlayerTwo"
azd env set MINECRAFT_OPERATORS "PlayerOne"
```

準備後のデプロイは、検証ゲートと権限・ポリシー確認を通過した上で `azd provision` を使用します。ワールドは停止状態（0 レプリカ）で開始します。AZD 出力の Container App 名とリソースグループ名を使って起動します。

```powershell
az containerapp update --name <container-app-name> --resource-group <resource-group-name> --min-replicas 1 --max-replicas 1
```

停止時は最小レプリカ数を 0 に戻します。ACA の 120 秒終了猶予内に Paper の保存・終了が完了したことをログで確認してください。

```powershell
az containerapp update --name <container-app-name> --resource-group <resource-group-name> --min-replicas 0 --max-replicas 1
```

### コスト、バックアップ、運用

- 主なコスト要因は、サーバー稼働中の D4 Dedicated Workload Profile、Log Analytics の取り込み・保持、Azure Files の容量/トランザクション、Private Endpoint、通信量です。0 レプリカへのスケール後もストレージ、Private Endpoint、ログ保持などの料金は残ります。実際の料金はリージョンと利用量に依存するため、作成前に [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) で見積もってください。
- Storage の 7 日 soft delete は誤削除対策です。障害・破損・誤操作に備え、Azure Backup で共有の定期保護と保持期間を別途設定してください。バックアップから別共有へ復元し、起動確認する手順を事前にテストします。
- 起動前に whitelist/OP 設定とプレイヤーのゲームバージョンを確認します。起動後は ACA ログと Minecraft 接続を確認し、停止は 0 レプリカへ変更してから Paper の正常終了を確認します。
- Azure Files SMB MI が利用できない、管理グループポリシーが対象リソースを拒否する、または RBAC 付与権限がない場合は、共有キー方式へ自動フォールバックせず、デプロイを停止して設計を見直します。

## 検証と旧テンプレート

`.azure/deployment-plan.md` は今回の構成と未解決の Azure 検証ゲートを記録します。`azure-validate` による検証完了前に `azd provision`、`azd up`、Azure デプロイコマンドを実行しないでください。既存の `bicep/mcserver.bicep` は以前の Azure Firewall/ストレージキー構成、`bicep/deploymcvm.bicep` は SSH キーを使う旧 VM 構成です。これらは新しい構成の代わりに使用しないでください。

## 参考資料

- [Paper project setup](https://docs.papermc.io/paper/dev/project-setup/) / [plugin.yml](https://docs.papermc.io/paper/dev/plugin-yml/)
- [itzg Minecraft Server on Docker: Java versions](https://docker-minecraft-server.readthedocs.io/en/latest/versions/java/) / [server properties](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/server-properties/)
- [ACA storage mounts](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts) / [Azure Files managed identities](https://learn.microsoft.com/en-us/azure/storage/files/files-managed-identities) / [ACA ingress](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview) / [ACA application lifecycle](https://learn.microsoft.com/en-us/azure/container-apps/application-lifecycle-management)
- [AZD environment variables](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/manage-environment-variables) / [Azure Files backup overview](https://learn.microsoft.com/en-us/azure/backup/azure-file-share-backup-overview)