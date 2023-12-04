var sshpubkey = loadTextContent('../../.ssh/id_rsa.pub') // SSH 公開鍵を相対パスで指定

module deployvnet './modules/vnet.bicep' = {
  name: 'vnet'
  params: {
    addressPrefix: '10.1.0.0/16'
    virtualNetworkName: 'vnet'
    subnetName: 'default'
    subnetAddressPrefix: '10.1.0.0/24'
  }
}

module deployvm './modules/ubuntuvm.bicep' = {
  name: 'vm'
  params: {
    vmName: 'mcsvr'
    adminPasswordOrKey: '${sshpubkey}'
    virtualNetworkName: 'vnet'
    subnetName: 'default'
    srcAddress: '*' // 接続元 IP アドレスを指定
  }
  dependsOn: [
    deployvnet
  ]
}
