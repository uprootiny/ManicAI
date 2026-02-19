# Download Page Deployment

Serve `docs/download/index.html` at:

- `https://manicai.hypersticial.art/`

The page resolves the latest successful `build-macos.yml` run from GitHub Actions and links to artifact downloads via `nightly.link`.

## Caddy Example

```caddy
manicai.hypersticial.art {
    root * /srv/manicai-download
    file_server
}
```

Deploy files:

```bash
mkdir -p /srv/manicai-download
cp /path/to/ManicAI/docs/download/index.html /srv/manicai-download/index.html
```

## Nginx Example

```nginx
server {
    listen 80;
    server_name manicai.hypersticial.art;
    root /srv/manicai-download;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

## Notes

- This is a static page; no backend needed.
- GitHub API is queried client-side.
- If GitHub rate-limits unauthenticated traffic, reload later or add a server-side cache proxy.
