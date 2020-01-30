# Divvy API

The API component connects client apps the the Fabric network.

```
$ docker build -t trinsiclabs/divvy-api .
```

```
$ docker-compose up -d
```

```
$ docker exec api.divvy.com node ./lib/security.js enrolladmin org1
```

```
$ docker exec api.divvy.com node ./lib/security.js registeruser org1 user1
```

```
$ docker exec api.divvy.com node ./lib/query.js \
    -o org1 \
    -u user1 \
    -c org1-channel \
    -n share \
    -m queryShare \
    -a '["org1","1"]'
```
