# Requirements
## Docker
### Linux
https://docs.docker.com/v17.12/install/linux/docker-ce/binaries/
### Windows
https://docs.docker.com/docker-for-windows/install/
## Clients
Clients must be in the "clients" folder. Put the contents of the WotLK folder into "clients/3.3.5". Put the contents of the BfA folder into "clients/8.2.0".
For WotLK, the folder structure should look like:
```
clients
    3.3.5
        Data
        Interface
        {other files}
```
For BfA, the folder structure should look like:
```
clients
    8.2.0
        _classic_
        _retail_
        Data
        {other files}
```

# Scripts
## Linux
This is unreleased and is currently in development.

## Windows
### run.bat
All in one. Builds from source, adds project, starts project. Will passthru arguments.
### build.ps1
```
-repo "git://..."
	default: "github.com/TrinityCore/TrinityCore.git"
-branch "master" or "3.3.5"
	default: "master"
```	
This script will clone (or update/pull) the TrinityCore source and build it. The repository can be changed, but for most people, the only argument you'll want to change is the branch. For BfA, use "master". For WotLK, use "3.3.5". 
 
### add_project.ps1
```
-project "Name of Project"
	default: "untitled"
-version "8.2.0" or "3.3.5"
	default: "8.2.0"
-realms "Trinity,Scarlet,Molten"
	default: "Trinity"
-development $false
	default: $false
```	
This script will create a project folder and copy the necessary files for an authentication server and any specified (comma delimited) realms. One project can have both 3.3.5 and 8.2.0 world servers, but they will use separate authentication servers. One project will only have one authentication server for each version.
	
### start_project.ps1
```
-project "Name of Project"
	default: "untitled"
-version "8.2.0" or "3.3.5"
	default: "8.2.0"
-realms "Trinity,Scarlet,Molten"
	default ""
```	
This script will start up all the containers necessary for a given project. If realms argument is not set all realms for that project will be started.

# Remote Access (Administration)
When a worldserver/realm is started, the telnet port for RA will be shown. By default, the authserver will have an account "admin" with the password "admin" set up for RA. It would be very wise to change this immediately.
From RA:
```
account set password admin new_password new_password
```

# Client Access
https://trinitycore.atlassian.net/wiki/spaces/tc/pages/74006268/Client+Setup
## 3.3.5
Data/enUS/realmlist.ftw
```
set realmlist url.to.authserver:port_number
```
## 8.2.0
\_retail\_/WTF/Config.wtf
```
SET portal "url.to.bnetserver:port_number"
```
### Custom Client Launcher
This is not required for WotLK, only for BfA clients.
https://arctium.io/ -> World of Warcraft -> Client Launchers -> Custom Server -> Windows/macOS -> 8.2.0.x - ... .zip
Put the executable in the same folder as the _retail_ folder
