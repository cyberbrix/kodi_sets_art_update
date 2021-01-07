#!/bin/bash


#Scans existing sets, downloads and assigns missing artwork. Ignores sets with less than 2 movies.

#change to location if different than below. Should be in user's home directory.
configfile="$HOME/.kodi_sets_art_update.ini"

#check for configuration file
if [ ! -f "$configfile" ]
then
echo "$configfile is missing"
exit 1
fi



#check if JQ installed
if ! type jq &> /dev/null
then 
echo "jq is not installed"
exit 1
fi

#default values for variables
api="NOTSET"
kodiip="NOTSET"
usern="NOTSET"
passw="NOTSET"
#local location to download images files. mostly likely the mounted share. 
#eg /mnt/artwork, which is on a remote server
downloaddir="NOTSET"
#mapping used by Kodi. this is how Kodi will find the files.
#eg: smb://192.169.10.1/collectionart/
#not directly referenced by the host running the script, just assigned via API
imagelocation="NOTSET"


#Import variables from config
. $configfile


#Validate variables
if [ "$api" = "NOTSET" ] || [ "$kodiip" = "NOTSET" ] || [ "$usern" = "NOTSET" ] || [ "$passw" = "NOTSET" ] || [ "$downloaddir" = "NOTSET" ] || [ "$imagelocation" = "NOTSET" ]
then
echo "variables not set in $configfile file"
echo "TheMovieDB API: $api"
echo "Kodi IP:port: $kodiip"
echo "username: $usern"
echo "password: <not shown>"
echo "download dir: $downloaddir"
echo "image location: $imagelocation"
exit 1
fi

#Create function to decode urls
urldecode(){   echo -e "$(sed 's/+/ /g;s/%\(..\)/\\x\1/g;')"; }

# get base config
baseurl=`curl -s "https://api.themoviedb.org/3/configuration?api_key=$api" | jq -r '.images.base_url'`

if [ $baseurl == null ]
then
echo "issue with API or TheMovieDB"
exit 1
fi

baseimage=$baseurl"original"

#Test Kodi Connectivity
kodicheck=`curl -s --header 'Content-Type: application/json' --data-binary '{"id": 1, "jsonrpc": "2.0", "method":"JSONRPC.Ping"}' "http://$usern:$passw@$kodiip/jsonrpc" | jq -r '.result'`

if [ "$kodicheck" != "pong" ]
then
echo "Kodi API connectivity issue"
exit 1
fi

#detect total number of movie sets
totalsets=`curl -s --header 'Content-Type: application/json' --data-binary '{"id": 1, "jsonrpc": "2.0", "method":"VideoLibrary.GetMovieSets"}' "http://$usern:$passw@$kodiip/jsonrpc" | jq -r '.result.limits.total'`

#list all movies
allmovies=`curl -s --header 'Content-Type: application/json' --data-binary '{"id": 1, "jsonrpc": "2.0", "method":"VideoLibrary.GetMovieSets","params": { "properties": ["title","art"]}}' "http://$usern:$passw@$kodiip/jsonrpc" | jq -r '.result.sets[] | "\(.title)|\(.setid)|\(.art.fanart)|\(.art.poster)"'`

#List all existing folderart
filelist=$(mktemp XXXXXXXX.tmp 2>&1)
tempfilestat=$?

if [ $tempfilestat -eq 0 ]
then
ls -1 $downloaddir*.jpg | sed "s/${downloaddir//\//\\/}//g" > $filelist
else
echo "unable to create temp file"
fi

globalchange=0
while IFS='|' read a b c d

do

  collnameraw="$a"
  collname=`echo "$collnameraw" | sed 's/[<>:"/\|?*]//'`
  movieset="$b"
  fanart="$c"
  poster="$d"

  currposter=`echo $poster | urldecode | sed 's/^image:\/\///; s/\/$//'`
  currfanart=`echo "$fanart" | urldecode | sed 's/^image:\/\///; s/\/$//'`

  properposter=$imagelocation$collname"-poster.jpg"
  properfanart=$imagelocation$collname"-fanart.jpg"

  totalmovies=`curl -s --header 'Content-Type: application/json' --data-binary '{"id": 1, "jsonrpc": "2.0", "method":"VideoLibrary.GetMovieSetDetails","params":{"setid": '$movieset'}}' "http://$usern:$passw@$kodiip/jsonrpc" | jq -r '.result.setdetails.limits.total'`


  if ! [[ "$totalmovies" =~ ^[0-9]+$ ]]
  then
    echo "$collname movies count not found"
    continue
  fi

  #checking movie count. skipping collections with 1 movie
  if [ $totalmovies -lt 2 ]
  then
    continue
  fi

  #Getting collection poster and fanart file paths
  setinfo=`curl -sG --data-urlencode "page=1" --data-urlencode "language=en-US" --data-urlencode "api_key=44fca1785541f7e5132635539343740f" --data-urlencode "query=$collnameraw" https://api.themoviedb.org/3/search/collection | jq -r --arg collect "$collnameraw" '.results[] | select (.name==$collect)'`
  #read A B <<< `curl -sG --data-urlencode "page=1" --data-urlencode "language=en-US" --data-urlencode "api_key=44fca1785541f7e5132635539343740f" --data-urlencode "query=$collnameraw" https://api.themoviedb.org/3/search/collection | jq -r --arg collect "$collnameraw" '.results[] | select (.name==$collect) | .backdrop_path, .poster_path'`
  A=`echo $setinfo  | jq -r .backdrop_path` 
  B=`echo $setinfo  | jq -r .poster_path`

  #assign file system file name
  fileposter=$downloaddir$collname"-poster.jpg"
  filefanart=$downloaddir$collname"-fanart.jpg"

  #check if proper poster - file can still be missing, but set correctly in Kodi
  posterfix=0
  if [ "$currposter" != "$properposter" ]
  then
    echo "$collname poster mismatch"
    #echo "CURRENT: $currposter"
    #echo "PROPER: $properposter"
    posterfix=1
    globalchange=1
fi

#check if proper fanart - file can still be missing, but set correctly in Kodi
fanartfix=0
if [ "$currfanart" != "$properfanart" ]
then
echo "$collname fanart mismatch"
#echo "CURRENT: $currfanart"
#echo "PROPER: $properfanart"
fanartfix=1
globalchange=1
fi

#checking if current poster file exists
if [ ! -f "$fileposter" ] && [ "$B" != "null" ]
then
#attempt to download file
echo "Poster missing, downloading $fileposter"
wget -qO "$fileposter" "$baseimage""$B"
#if fails, deletes file
if [ $? -ne 0 ]
then
echo "poster: $baseimage$B wget error"
rm -f "$fileposter"
else
#echo "poster: $baseimage$B wget success"
sleep 5
fi
fi


#checking if current fanart file exists
if [ ! -f "$filefanart" ] && [ $A != "null" ]
then
#attempt to download file
echo "Fanart missing, downloading $filefanart"
wget -qO "$filefanart" "$baseimage""$A"
#if fails, deletes file
if [ $? -ne 0 ]
then
echo "fanart: $baseimage$A wget error"
rm -f "$filefanart"
else
#echo "fanart: $baseimage$A wget success"
sleep 5
fi
fi
#Set poster of collection
if [ -f "$fileposter" ] && [ $posterfix -eq 1 ]
then
#set poster
#echo "Setting poster - $properposter"
postersetresult=$(curl -s --header 'Content-Type: application/json' --data-binary '{"id": 1, "jsonrpc": "2.0", "params":{"setid":'$movieset', "art": {"poster": "'"$properposter"'"}}, "method": "VideoLibrary.SetMovieSetDetails"}' "http://$usern:$passw@$kodiip/jsonrpc" | grep -iq "OK" ; echo $?)
if [ $postersetresult -eq 0 ]
then
echo "$collname poster set"
else
echo "$collname poster not set"
fi
fi


#Set fanart of collection
if [ -f "$filefanart" ] && [ $fanartfix -eq 1 ]
then
#set fanart
#echo "Setting fanart - $properfanart"
fanartsetresult=$(curl -s --header 'Content-Type: application/json' --data-binary '{"id": 1, "jsonrpc": "2.0", "params":{"setid":'$movieset', "art": {"fanart": "'"$properfanart"'"}}, "method": "VideoLibrary.SetMovieSetDetails"}' "http://$usern:$passw@$kodiip/jsonrpc" | grep -iq "OK" ; echo $?)
if [ $fanartsetresult -eq 0 ]
then
echo "$collname fanart set"
else
echo "$collname fanart not set"
fi
fi

#Remove existing art from temp list


if [ $tempfilestat -eq 0 ]
then
sed -i "/^$collname-poster.jpg$/d;/^$collname-fanart.jpg$/d" $filelist
fi

done <<< "$allmovies"

if [ $globalchange -eq 0 ]
then
echo "No movie set art changes"
fi

# Listing unused files
if [ $tempfilestat -eq 0 ]
then

#removing excepted art from list
IFS=';'
for item in $artexception
do
sed -i "/$item/d" $filelist
done


echo ""
echo "******Extra artwork files*****"
cat $filelist
rm  $filelist
fi


exit 0
