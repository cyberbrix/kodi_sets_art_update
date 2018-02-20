# kodi_sets_art_update
#A linux bash script to ensure that movie set posters and fanart are properly set. 
#Should work for SQL and local libraries, as it only touches KODI.
#If there are multiple instances of KODI sharing a DB, a single update will update all
#### NOTE: It will not correct incorrect images with the proper file name.

#output is text, so it can be redirected
#blank output means no changes
#
#After cloning the repository, perform the following, if needed
#cd kodi_sets_art_update/
#chmod a+x kodi_sets_art_update.sh

#Run in bash, requires jq

#https://stedolan.github.io/jq/

#Create a .movieset_art_fix.ini in users $HOME directory
#.kodi_sets_art_update.ini contents should be followling lines.

#tvdb API key -no quotes needed
api=
#kodi IP/port (if not 80) eg 192.168.1.1:8080
kodiip=
#kodi HTTP username
usern=
#kodi HTTP password
passw=

#local location to download images files. mostly likely the mounted share.
#eg "/mnt/artwork", which is on a remote server
downloaddir=

#mapping used by Kodi. this is how Kodi will find the files.
#like "smb://192.169.10.1/collectionart/"
#eg: imagelocation="smb://192.169.10.1/collectionart/"
#not directly referenced by the host running the script, just assigned via API
imagelocation=

