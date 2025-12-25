// Cloudflare Worker for images.windsorcli.dev
// Proxies GitHub releases and adds Incus-Image-Hash header
// Supports: /{repo}/{version}/{filename}
// Example: /talos-incus/v1.12.0/incus-amd64.tar.gz
//
// Hashes are pre-calculated in CI and stored in Cloudflare KV

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    // Extract repo, version, and filename from path
    // Format: /{repo}/{version}/{filename}
    // Example: /talos-incus/v1.12.0/incus-amd64.tar.gz
    const pathMatch = url.pathname.match(/^\/([^\/]+)\/(v[\d.]+)\/(.+)$/);
    if (!pathMatch) {
      return new Response('Invalid path. Use: /{repo}/{version}/{filename}', { 
        status: 400,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
    
    const [, repo, version, filename] = pathMatch;
    
    // Extract architecture from filename and normalize
    const archMatch = filename.match(/([a-z0-9_]+)\.tar\.gz$/);
    if (!archMatch) {
      return new Response('Invalid filename format. Expected: *.tar.gz', { 
        status: 400,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
    
    // Extract architecture identifier (everything before .tar.gz)
    let arch = archMatch[1];
    
    // If filename has a prefix (e.g., "incus-amd64"), extract just the arch part
    if (arch.includes('-')) {
      const parts = arch.split('-');
      arch = parts[parts.length - 1]; // Take the last part (the architecture)
    }
    
    // Normalize to Incus standard architecture names
    const archMap = {
      'aarch64': 'arm64',      // ARM 64-bit
      'arm64': 'arm64',        // Already correct
      'x86_64': 'amd64',       // x86 64-bit
      'x64': 'amd64',          // x64 shorthand
      'amd64': 'amd64',        // Already correct
    };
    
    arch = archMap[arch.toLowerCase()] || arch;
    
    // Get pre-calculated hash from KV store
    // Key format: {repo}:{version}:{arch}
    // Example: talos-incus:v1.12.0:amd64
    const kvKey = `${repo}:${version}:${arch}`;
    const hash = await env.IMAGE_HASHES.get(kvKey);
    
    if (!hash) {
      return new Response(`Hash not found for ${repo}/${version}/${arch}. Image may not be available yet.`, { 
        status: 404,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
    
    // GitHub releases URL (source)
    const githubUrl = `https://github.com/windsorcli/${repo}/releases/download/${version}/${filename}`;
    
    // Proxy URL (where user is downloading from)
    const proxyUrl = `${url.protocol}//${url.host}${url.pathname}`;
    
    try {
      // Fetch from GitHub (streaming, don't load entire file into memory)
      const response = await fetch(githubUrl);
      
      if (!response.ok) {
        return new Response(`GitHub error: ${response.status}`, { 
          status: response.status,
          headers: { 'Content-Type': 'text/plain' }
        });
      }
      
      // Clone response and add required Incus headers
      const newHeaders = new Headers(response.headers);
      
      // Required headers
      newHeaders.set('Incus-Image-Hash', hash);
      newHeaders.set('Incus-Image-URL', proxyUrl);

      // CORS header
      newHeaders.set('Access-Control-Allow-Origin', '*');
      
      // Return streaming response with headers
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders
      });
    } catch (error) {
      return new Response(`Error: ${error.message}`, { 
        status: 500,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
  }
};
