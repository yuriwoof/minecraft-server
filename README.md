# minecraft-server

## デプロイ方法

### Azure Container Apps へのデプロイ（推奨）

Azure Container Apps と Azure Files を使用して、Minecraft Java Edition サーバーをデプロイする方法です。詳細は [bicep/README.md](./bicep/README.md) を参照してください。

#### テンプレートの種類

**1. minecraft-containerapp.bicep（シンプル版）**
- 開発・テスト環境、小規模なプライベートサーバー向け
- 基本的な構成で迅速にデプロイ可能

**2. mcserver.bicep（エンタープライズ版）**
- 本番環境、セキュリティ要件が高い環境向け
- Azure Firewall、Private Endpoint によるセキュアな構成

#### クイックスタート

```bash
# リソースグループの作成
az group create \
  --name <resource-group-name> \
  --location japaneast

# シンプル版のデプロイ
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file ./bicep/minecraft-containerapp.bicep

# エンタープライズ版のデプロイ（shortName パラメータが必須）
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file ./bicep/mcserver.bicep \
  --parameters shortName='mc001'
```

詳細なパラメータ、設定方法、トラブルシューティングは [bicep/README.md](./bicep/README.md) をご覧ください。

---

### 仮想マシンへのデプロイ（従来の方法）

#### VM のデプロイ

```bash
$ az group create -n <resource-group-name> -l <location>
$ az deployment group create -g <resource-group-name> --template-file ./<this-repository>/deploymcvm.bicep
```

#### Minecraft Server のデプロイ

* `docker-compose.yaml` を Azure VM にコピーし、同じ階層に `data` ディレクトリを作成
  * `setworldspawn` コマンドで初期スポーン座標を設定しています。不要な場合は削除してください
* Azure VM で `docker-compose up` を実行。コンソールにエラーがないことを確認後、`Ctrl+C` で停止
* [GeyserMC Download page](https://geysermc.org/download) から `Geyser-Spigot.jar` と `floodgate-spigot.jar` をダウンロードし、`plugins` ディレクトリにコピー
* `docker-compose up -d` を実行

## 参考資料

### Azure Container Apps デプロイメント
- [Bicep テンプレート詳細ドキュメント](./bicep/README.md)
- [Azure Container Apps ドキュメント](https://learn.microsoft.com/ja-jp/azure/container-apps/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)

### Minecraft サーバー
- [Minecraft Server on Docker (Java Edition)](https://docker-minecraft-server.readthedocs.io/en/latest/)
- [itzg/minecraft-server GitHub](https://github.com/itzg/docker-minecraft-server)