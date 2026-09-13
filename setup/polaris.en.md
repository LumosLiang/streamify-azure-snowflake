# Set Up Polaris and PostgreSQL on the Spark Master

[中文](polaris.md) | English

Polaris and its PostgreSQL metadata database run in Docker containers on the Spark Master VM. This step only starts the catalog service; it does not create an Iceberg catalog or tables.

## 1. Prepare the VM

```bash
ssh streamify-spark
cd ~/streamify
bash scripts/vm_setup.sh
```

If Docker was just installed, log out and reconnect before continuing.

## 2. Create the local configuration

```bash
cd ~/streamify/polaris
cp .env.example .env
```

Edit `.env` and set a different random value for each variable:

```bash
openssl rand -hex 24
```

`.env` is ignored by Git and must not be committed. Keep `POLARIS_CLIENT_ID` and `POLARIS_CLIENT_SECRET`; they are the credentials of the initial root principal.

## 3. Start for the first time and verify

```bash
docker compose up -d
docker compose ps
docker compose logs bootstrap
curl http://localhost:8182/q/health
```

`bootstrap` creates the `POLARIS` realm once and then exits normally. PostgreSQL and Polaris remain running. The API uses port `8181`; management and health checks use `8182`.

To inspect or stop the services later:

```bash
docker compose logs --follow polaris
docker compose down
```

Do not run `docker compose down -v`; it deletes the Polaris metadata stored in the PostgreSQL volume.
