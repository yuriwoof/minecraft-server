# Azure Secure Architecture Feasibility Study

## 現在のアーキテクチャ概要

本Minecraftサーバーは以下のAzureリソースで構成されています：

### ネットワーク構成
- **Virtual Network (VNet)**: 10.1.0.0/16
- **Subnet**: 10.1.0.0/24
- **Public IP Address**: Basic SKU、Dynamic割り当て
- **Network Security Group (NSG)**: 以下のインバウンドルールを設定
  - SSH (TCP/22): 管理用
  - Minecraft Java Edition (TCP/25565): ゲームクライアント接続用
  - Minecraft Bedrock Edition (UDP/19132): クロスプラットフォーム接続用

### コンピュート構成
- **VM**: Standard_D2_v4
- **OS**: Ubuntu 22.04 LTS
- **Storage**: Standard_LRS
- **認証**: SSH公開鍵認証

## Azure における DDoS 対策

Minecraftサーバーは公開インターネット上で稼働するため、DDoS攻撃の標的になりやすい特性があります。以下、Azureで実装可能なDDoS対策を検討します。

### 1. Azure DDoS Protection

#### 1.1 DDoS Protection Standard
**概要**:
- Azure DDoS Protection Standardは、VNetレベルでの包括的なDDoS防御を提供
- L3/L4レイヤーの攻撃に対する自動的な緩和策を実装
- リアルタイムの攻撃メトリクスとアラート機能

**実装方法**:
```bicep
resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2023-05-01' = {
  name: 'minecraft-ddos-protection'
  location: location
  properties: {}
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    enableDdosProtection: true
    ddosProtectionPlan: {
      id: ddosProtectionPlan.id
    }
  }
}
```

**メリット**:
- SYN Flood、UDP Flood、ICMP Floodなどの一般的な攻撃を自動検出・緩和
- Azure Monitor統合による可視性向上
- コスト保護保証（攻撃時のスケールアウトコストをMicrosoftが負担）

**デメリット**:
- 月額約$2,944 USD（固定コスト）+ 保護対象Public IPあたり約$30 USD/月
- 小規模環境には高コスト

**推奨度**: ★★☆（中規模以上のプロダクション環境向け）

#### 1.2 DDoS Network Protection（従量課金モデル）
**概要**:
- 2023年に導入された新しいDDoS保護オプション
- Public IPごとに課金される従量課金モデル
- DDoS Protection Standardと同等の保護機能

**実装方法**:
```bicep
resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIPAddressName
  location: location
  sku: {
    name: 'Standard'  // Standard SKUが必須
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    ddosSettings: {
      protectionMode: 'Enabled'
    }
  }
}
```

**メリット**:
- 小規模環境でも導入しやすい従量課金モデル
- Public IPごとに有効化可能
- DDoS Protection Standardと同等の保護レベル

**デメリット**:
- Standard SKU Public IPが必須（Basic SKUでは利用不可）
- 保護対象Public IPあたり月額課金

**推奨度**: ★★★（小〜中規模環境に最適）

### 2. Network Security Group (NSG) による防御強化

#### 2.1 ソースIPアドレス制限の厳格化
**現状の課題**:
現在の実装では `srcAddress: '*'` となっており、全世界からのアクセスを許可しています。

**改善策**:
```bicep
// 既知のプレイヤーのIPレンジに制限
param allowedSourceIPs array = [
  'xxx.xxx.xxx.xxx/32'  // 特定のIPアドレス
  'yyy.yyy.yyy.0/24'    // 特定のネットワーク範囲
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      for (i, ip) in allowedSourceIPs: {
        name: 'AllowMinecraft-${i}'
        properties: {
          priority: 1000 + i
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: ip
          destinationPortRange: '25565'
        }
      }
    ]
  }
}
```

**メリット**:
- 追加コストなし
- 即座に実装可能
- 攻撃対象範囲を大幅に削減

**デメリット**:
- プレイヤーのIPアドレスが固定でない場合は運用が困難
- 新しいプレイヤー追加時に設定更新が必要

**推奨度**: ★★★（プライベートサーバー向け）

#### 2.2 Service Tagの活用
特定の地域からのアクセスのみを許可する場合:

```bicep
sourceAddressPrefix: 'AzureCloud.JapanEast'  // 日本東リージョンのAzure IPのみ許可
```

### 3. Azure Firewall による高度な防御

#### 3.1 Azure Firewall Standard
**概要**:
- ステートフルなネットワークファイアウォール
- FQDN フィルタリング、ネットワークルール、アプリケーションルールを提供
- 脅威インテリジェンスベースのフィルタリング

**アーキテクチャ**:
```
Internet
    ↓
Azure Firewall (Hub VNet)
    ↓
Minecraft Server (Spoke VNet)
```

**実装コンポーネント**:
```bicep
resource firewallPublicIP 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'minecraft-fw-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource azureFirewall 'Microsoft.Network/azureFirewalls@2023-05-01' = {
  name: 'minecraft-firewall'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    ipConfigurations: [
      {
        name: 'configuration'
        properties: {
          publicIPAddress: {
            id: firewallPublicIP.id
          }
          subnet: {
            id: firewallSubnet.id
          }
        }
      }
    ]
    natRuleCollections: [
      {
        name: 'minecraft-nat-rules'
        properties: {
          priority: 200
          action: {
            type: 'Dnat'
          }
          rules: [
            {
              name: 'minecraft-java'
              protocols: ['TCP']
              sourceAddresses: ['*']
              destinationAddresses: [firewallPublicIP.properties.ipAddress]
              destinationPorts: ['25565']
              translatedAddress: vmPrivateIP
              translatedPort: '25565'
            }
            {
              name: 'minecraft-bedrock'
              protocols: ['UDP']
              sourceAddresses: ['*']
              destinationAddresses: [firewallPublicIP.properties.ipAddress]
              destinationPorts: ['19132']
              translatedAddress: vmPrivateIP
              translatedPort: '19132'
            }
          ]
        }
      }
    ]
    threatIntelMode: 'Alert'  // または 'Deny'
  }
}
```

**メリット**:
- 脅威インテリジェンスによる既知の悪意あるIPアドレスの自動ブロック
- 詳細なロギングとモニタリング
- 複数のサーバーを1つのFirewallで保護可能

**デメリット**:
- 高コスト（約$1.25/時間 + データ処理費用）
- ネットワークアーキテクチャの大幅な変更が必要
- Minecraftのような単一アプリケーションには過剰

**推奨度**: ★☆☆（複数サーバー環境または企業利用向け）

### 4. Application Gateway / Azure Front Door

#### 4.1 Application Gateway
**評価**: ❌ **非推奨**
- HTTP/HTTPSトラフィック専用
- MinecraftのTCP/UDPトラフィックには対応不可

#### 4.2 Azure Front Door
**評価**: ❌ **非推奨**
- HTTP/HTTPSベースのアプリケーション向け
- Minecraftサーバーには適用不可

### 5. Azure Bastion によるSSH接続の保護

**概要**:
SSH管理接続をインターネットから隔離し、Azure Bastion経由でのみアクセス可能にする。

**実装方法**:
```bicep
// Bastion用サブネットの追加
resource bastionSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  parent: virtualNetwork
  name: 'AzureBastionSubnet'  // 名前は固定
  properties: {
    addressPrefix: '10.1.1.0/26'  // /26以上が必須
  }
}

resource bastionPublicIP 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: 'bastion-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-05-01' = {
  name: 'minecraft-bastion'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'configuration'
        properties: {
          publicIPAddress: {
            id: bastionPublicIP.id
          }
          subnet: {
            id: bastionSubnet.id
          }
        }
      }
    ]
  }
}

// VM用Public IPを削除し、NSGからSSHルールを削除
// VMへのアクセスはAzure Portalまたは Azure CLI経由のBastionのみ
```

**メリット**:
- SSH接続に対するブルートフォース攻撃を完全に防止
- Public IP削減により攻撃対象範囲を縮小
- MFA統合によるセキュリティ強化

**デメリット**:
- 月額約$140 USD（Basic SKU）
- ブラウザベースのSSH接続（ローカルSSHクライアント使用不可）

**推奨度**: ★★☆（セキュリティ要件が高い環境向け）

### 6. Rate Limiting / Connection Limiting

#### 6.1 サーバーレベルでの実装
Minecraftサーバー自体の設定ファイル（server.properties）で接続制限を設定:

```properties
# server.properties
network-compression-threshold=256
max-players=20
rate-limit=0  # 0は無制限、設定推奨値は3000-6000
```

**メリット**:
- 無料で実装可能
- アプリケーションレベルでの制御

**デメリット**:
- ネットワークレベルの大規模攻撃には効果が限定的

#### 6.2 iptablesによるパケットフィルタリング
VM内でiptablesを使用した接続数制限:

```bash
# 同一IPからの接続数を制限
iptables -A INPUT -p tcp --dport 25565 -m connlimit --connlimit-above 3 -j REJECT
iptables -A INPUT -p udp --dport 19132 -m connlimit --connlimit-above 3 -j REJECT

# SYN Flood対策
iptables -A INPUT -p tcp --syn -m limit --limit 1/s --limit-burst 3 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP
```

**メリット**:
- 無料で実装可能
- 柔軟な制御が可能

**デメリット**:
- VM自体が大量のトラフィックを受けるため、帯域幅コストが発生
- CPU/メモリリソースを消費

**推奨度**: ★★★（基本的な保護として推奨）

### 7. 監視とアラート

#### 7.1 Azure Monitor / Network Watcher
**実装すべきメトリクス監視**:
```bicep
resource metricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-network-traffic-alert'
  location: 'global'
  properties: {
    severity: 2
    enabled: true
    scopes: [
      networkInterface.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'BytesReceivedRate'
          metricName: 'BytesReceivedRate'
          operator: 'GreaterThan'
          threshold: 10000000  // 10MB/s
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}
```

**監視項目**:
- Network In/Out バイト数
- CPU使用率
- メモリ使用率
- ディスクIOPS
- パケットドロップ数

**推奨度**: ★★★（必須）

## 推奨実装プラン

### 最小構成（個人利用・テスト環境）
**総コスト**: 追加費用 $0-50/月
1. ✅ **NSG強化**: ソースIP制限を実装
2. ✅ **iptables設定**: VM内での接続数制限
3. ✅ **Azure Monitor**: 基本的なメトリクス監視
4. ⚠️ **Standard Public IP**: 将来のDDoS Protection有効化に備える

### 標準構成（小規模コミュニティサーバー）
**総コスト**: 追加費用 $30-80/月
1. ✅ **DDoS Network Protection**: Public IPレベルの保護
2. ✅ **Standard Public IP**: Static割り当て
3. ✅ **NSG強化**: 地域ベースのフィルタリング
4. ✅ **Azure Monitor + Alert**: 異常検知とアラート
5. ✅ **iptables設定**: 多層防御
6. ✅ **Azure Bastion**: SSH接続の保護（オプション）

### エンタープライズ構成（大規模サーバー・商用利用）
**総コスト**: 追加費用 $3,000+/月
1. ✅ **DDoS Protection Standard**: VNet全体の保護
2. ✅ **Azure Firewall**: 集中管理と脅威インテリジェンス
3. ✅ **Azure Bastion**: 管理接続の完全隔離
4. ✅ **Azure Monitor + Log Analytics**: 詳細なロギングと分析
5. ✅ **複数リージョン展開**: 可用性向上

## セキュリティベストプラクティス

### 1. 多層防御（Defense in Depth）
複数のセキュリティレイヤーを組み合わせることで、単一の防御策が突破されても保護を維持:
- ネットワークレベル: NSG、DDoS Protection
- VMレベル: iptables、fail2ban
- アプリケーションレベル: Minecraftサーバー設定

### 2. 最小権限の原則
- 必要最小限のポートのみを開放
- SSH接続は公開鍵認証のみ許可
- 管理者権限は必要な時のみ使用

### 3. 定期的な監査とレビュー
- NSGルールの定期的な見直し
- 不要なルールの削除
- アクセスログの定期的な確認

### 4. バックアップとディザスタリカバリ
- 定期的なワールドデータのバックアップ
- Azure Backup の活用
- 復旧手順の文書化とテスト

## まとめ

AzureにおけるマインクラフトサーバーへのDDoS対策は、環境の規模と予算に応じて選択可能です：

**即座に実装すべき対策（無料〜低コスト）**:
1. Standard Public IPへの移行
2. NSGルールの最適化
3. iptablesによる接続制限
4. Azure Monitorでの監視設定

**予算に応じて追加すべき対策**:
- 小〜中規模: DDoS Network Protection（$30-50/月）
- 大規模: DDoS Protection Standard（$3,000/月）

**長期的な検討事項**:
- Azure Bastionによる管理接続の保護
- 複数リージョンへの展開による可用性向上
- Azure Firewallによる統合セキュリティ管理

現在の構成から最も効果的な最初のステップは：
1. Public IPをStandard SKUに変更
2. DDoS Network Protectionを有効化
3. NSGルールでソースIP制限を実装
4. iptablesで接続数制限を設定
5. Azure Monitorでアラートを設定

これらの対策により、コストを抑えながらも実用的なDDoS保護を実現できます。
