#!/bin/bash

[ -z $WP_SECRET ] && echo "Secret WP_SECRET not populated in environment" && exit 1

export WORDPRESS_DATABASE_HOST=`echo $WP_SECRET T | jq -r '.host'`
export WORDPRESS_DATABASE_PORT_NUMBER=`echo $WP_SECRET | jq -r .port`
export WORDPRESS_DATABASE_NAME=`echo $WP_SECRET | jq -r .dbname`
export WORDPRESS_DATABASE_USER=`echo $WP_SECRET | jq -r .username`
export WORDPRESS_DATABASE_PASSWORD=`echo $WP_SECRET | jq -r .password`

/opt/bitnami/scripts/wordpress/entrypoint.sh /opt/bitnami/scripts/apache/run.sh