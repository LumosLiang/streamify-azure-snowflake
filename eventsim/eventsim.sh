#! /bin/bash
exec java -XX:+AggressiveOpts -XX:+UseG1GC -XX:+UseStringDeduplication -Xmx4G -jar eventsim-assembly-2.0.jar "$@"
