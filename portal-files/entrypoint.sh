#!/bin/bash

set -o errexit

if [[ $SKIP_ENTRYPOINT_CHMOD != "true" ]]; then

    # Make some directories writable for www-data
    if [ -d /portal/storage ]; then
    	chgrp -R www-data /portal/storage
    	chmod -R g+w /portal/storage
    fi
    
    if [ -d /portal/bootstrap/cache ]; then
    	chgrp -R www-data /portal/bootstrap/cache
    	chmod -R g+w /portal/bootstrap/cache
    fi

fi

# Generate API key for Mesh
envFile="/portal/.env"

if [ ! -f "$envFile" ] && [ -f "${envFile}.example" ]; then
	cp -a "${envFile}.example" "${envFile}"
fi 

. $envFile

# Generate app key if not existing
if [[ $AUTOGENERATE_APP_KEY != "false" ]]; then
	if [[ $APP_KEY == "" ]]; then
		php artisan key:generate
	fi
fi

# Generate Mesh API key if not existing
if [[ $AUTOGENERATE_MESH_API_KEY != "false" ]]; then

	if [[ $MESH_URL == "" ]]; then
		MESH_URL="http://mesh:8080"
	fi

	if [[ $MESH_APIKEY == "" ]] || (( ${#MESH_APIKEY} < 32 )); then
		echo "MESH_URL: $MESH_URL"
		waitForMesh.sh $MESH_URL 300
		echo "Generating new Mesh API key..."
		MESH_APIKEY=$(mesh-gen-token.sh $MESH_URL)
		echo "Generated new Mesh API token: $MESH_APIKEY"

		if grep -q "^MESH_APIKEY=.*" $envFile
		then
			# When the .env file is a mount, --in-place of sed doesn't work, because
			# it creates a temporary file and trys to rename it. So we use a temp file instead.
			sed_temp_file=$(mktemp /tmp/sed_temp_file.XXXXXX)
			sed "s/MESH_APIKEY=.*/MESH_APIKEY=\"$MESH_APIKEY\"/g" $envFile > $sed_temp_file
			cp $sed_temp_file $envFile
		else
			echo "" >> $envFile
			echo "MESH_URL=\"$MESH_URL\"" >> $envFile
			echo "MESH_APIKEY=\"$MESH_APIKEY\"" >> $envFile
		fi
	fi

else
	echo "Skipping Mesh API Key auto-generation"
fi

if [[ $XDEBUG_ENABLED == "true" ]]; then
	echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" > /usr/local/etc/php/conf.d/load-xdebug.ini
fi

# Restrict apache2 from running as a service
update-rc.d apache2 disable

docker-php-entrypoint $@