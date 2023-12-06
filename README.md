# minecraft-server

## Deploy Vm

```bash
$ az group create -n <resource-group-name> -l <location>
$ az deployment group create -g <resource-group-name> --template-file ./<this-repository>/deploymcvm.bicep
```

## Deploy Minecraft Server

* Copy ```docker-compose.yaml``` to Azure VM and create ```data``` directory on same level of docker-compose.yaml.
  * Please make sure that I set first spown coordinate with ```setworldspawn``` command. Please delete this if you don't need.
* Run ```docker-compose up``` on Azure VM. Once you confirm no error on console. Please stop docker-compose with ```Ctrl+C```.
* Download ```Geyser-Spigot.jar``` and ```floodgate-spigot.jar``` from [GeyserMC Download page](https://geysermc.org/download) and copy&paste jar files to ```plugins``` directory.
* Run ```docker-compose up -d```.