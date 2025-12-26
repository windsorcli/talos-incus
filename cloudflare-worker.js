/**
 * Cloudflare Worker for images.windsorcli.dev
 * 
 * Implements simplestream protocol for Incus image server.
 * 
 * Supports:
 * - /streams/v1/index.json - Lists available products (simplestreams index)
 * - /streams/v1/images.json - Full product metadata (simplestreams images)
 * - /{repo}/{version}/{filename} - Direct image download with Incus headers
 * 
 * @module cloudflare-worker
 */

/**
 * Retrieves the list of all product keys from Cloudflare KV.
 * 
 * Product keys follow the format: product:talos:{version}:{arch}:{variant}
 * Example: product:talos:v1.12.0:amd64:default
 * 
 * @param {Object} env - Cloudflare Worker environment with IMAGE_HASHES KV binding
 * @returns {Promise<string[]>} Array of product keys
 */
async function getAllProducts(env) {
  const productsListKey = 'products:list';
  const productsListJson = await env.IMAGE_HASHES.get(productsListKey);
  
  if (productsListJson) {
    try {
      return JSON.parse(productsListJson);
    } catch (e) {
      console.error('Failed to parse products list:', e);
      return [];
    }
  }
  
  return [];
}

/**
 * Retrieves all image metadata from KV and formats it as simplestreams products.
 * 
 * Builds the complete images.json structure with:
 * - Product metadata (aliases, arch, os, release, variant)
 * - Version entries with creation timestamps
 * - Item entries with file metadata (hash, size, path)
 * 
 * @param {Object} env - Cloudflare Worker environment with IMAGE_HASHES KV binding
 * @returns {Promise<Object>} Simplestreams images.json structure
 */
async function getAllImageMetadata(env) {
  const products = await getAllProducts(env);
  const images = {};
  
  for (const kvProductKey of products) {
    // KV key format: product:talos:{version}:{arch}:{variant}
    // Simplestreams key format: talos:{version}:{arch}:{variant} (no "product:" prefix)
    const parts = kvProductKey.split(':');
    if (parts.length !== 5 || parts[0] !== 'product') continue;
    
    const [prefix, os, version, arch, variant] = parts;
    
    // Get metadata for this product from KV
    const metadataJson = await env.IMAGE_HASHES.get(kvProductKey);
    
    if (metadataJson) {
      try {
        const metadata = JSON.parse(metadataJson);
        
        // Simplestreams product key (without "product:" prefix)
        const simplestreamsKey = `${os}:${version}:${arch}:${variant}`;
        
        if (!images[simplestreamsKey]) {
          images[simplestreamsKey] = {
            aliases: `talos/${version}/${arch}/${variant},talos/${version}/${arch}`,
            arch: arch,
            os: 'Talos',
            release: version,
            release_title: version,
            requirements: {},
            variant: variant,
            versions: {}
          };
        }
        
        // Convert unix timestamp to simplestreams version format: YYYYMMDD_HH:MM
        const creationDate = metadata.creation_date ? parseInt(metadata.creation_date) : Math.floor(Date.now() / 1000);
        const date = new Date(creationDate * 1000);
        const year = date.getUTCFullYear();
        const month = String(date.getUTCMonth() + 1).padStart(2, '0');
        const day = String(date.getUTCDate()).padStart(2, '0');
        const hours = String(date.getUTCHours()).padStart(2, '0');
        const minutes = String(date.getUTCMinutes()).padStart(2, '0');
        const versionKey = `${year}${month}${day}_${hours}:${minutes}`;
        
        // Path is relative to the simplestreams base URL
        // Incus will construct the full URL: {baseUrl}/{path}
        const imagePath = `talos-incus/${version}/incus-${arch}.tar.xz`;
        
        images[simplestreamsKey].versions[versionKey] = {
          items: {
            'incus.tar.xz': {
              ftype: 'incus.tar.xz',
              sha256: metadata.hash,
              size: metadata.size,
              path: imagePath,
              combined_sha256: metadata.hash,
              combined_rootxz_sha256: metadata.hash
            },
            'lxd.tar.xz': {
              ftype: 'lxd.tar.xz',
              sha256: metadata.hash,
              size: metadata.size,
              path: imagePath,
              combined_sha256: metadata.hash,
              combined_rootxz_sha256: metadata.hash
            }
          }
        };
      } catch (e) {
        console.error(`Failed to parse metadata for ${kvProductKey}:`, e);
      }
    }
  }
  
  return {
    format: 'products:1.0',
    content_id: 'images',
    datatype: 'image-downloads',
    products: images
  };
}

/**
 * Handles requests to /streams/v1/index.json
 * 
 * Returns the simplestreams index that lists all available products.
 * Clients use this to discover what products are available before
 * requesting the full images.json metadata.
 * 
 * @param {Object} env - Cloudflare Worker environment with IMAGE_HASHES KV binding
 * @returns {Promise<Response>} JSON response with index structure
 */
async function handleIndex(env) {
  const kvProducts = await getAllProducts(env);
  
  // Convert KV product keys (product:talos:...) to simplestreams format (talos:...)
  const simplestreamsProducts = kvProducts.map(kvKey => {
    const parts = kvKey.split(':');
    if (parts.length === 5 && parts[0] === 'product') {
      // Remove "product:" prefix: product:talos:v1.12.0:amd64:default -> talos:v1.12.0:amd64:default
      return parts.slice(1).join(':');
    }
    return null;
  }).filter(Boolean);
  
  const index = {
    index: {
      images: {
        datatype: 'image-downloads',
        path: 'streams/v1/images.json',
        format: 'products:1.0',
        products: simplestreamsProducts
      }
    },
    format: 'index:1.0'
  };
  
  return new Response(JSON.stringify(index, null, 2), {
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    }
  });
}

/**
 * Handles requests to /streams/v1/images.json
 * 
 * Returns the complete simplestreams images metadata for all products.
 * This includes full product information, version entries, and file metadata
 * (hashes, sizes, paths) for each image.
 * 
 * @param {Request} request - The incoming HTTP request (used to construct absolute URLs)
 * @param {Object} env - Cloudflare Worker environment with IMAGE_HASHES KV binding
 * @returns {Promise<Response>} JSON response with products structure
 */
async function handleImages(env) {
  const images = await getAllImageMetadata(env);
  
  return new Response(JSON.stringify(images, null, 2), {
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    }
  });
}

/**
 * Handles direct image download requests.
 * 
 * Proxies requests to GitHub Releases and adds required Incus headers:
 * - Incus-Image-Hash: SHA256 hash of the image file
 * - Incus-Image-URL: URL where the image is being served from
 * 
 * Path format: /{repo}/{version}/{filename}
 * Example: /talos-incus/v1.12.0/incus-amd64.tar.gz
 * 
 * @param {Request} request - The incoming HTTP request
 * @param {Object} env - Cloudflare Worker environment with IMAGE_HASHES KV binding
 * @param {Array} pathMatch - Regex match result from path pattern
 * @returns {Promise<Response>} Streaming response with image data and Incus headers
 */
async function handleImageDownload(request, env, pathMatch) {
  const [, repo, version, filename] = pathMatch;
  
  // Extract architecture from filename and normalize
  // Support both .tar.gz and .tar.xz for backward compatibility
  const archMatch = filename.match(/([a-z0-9_]+)\.tar\.(gz|xz)$/);
  if (!archMatch) {
    return new Response('Invalid filename format. Expected: *.tar.gz or *.tar.xz', { 
      status: 400,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  let arch = archMatch[1];
  if (arch.includes('-')) {
    const parts = arch.split('-');
    arch = parts[parts.length - 1];
  }
  
  // Normalize architecture names to Incus standard
  const archMap = {
    'aarch64': 'arm64',
    'arm64': 'arm64',
    'x86_64': 'amd64',
    'x64': 'amd64',
    'amd64': 'amd64',
  };
  arch = archMap[arch.toLowerCase()] || arch;
  
  // Get metadata from KV using unified product key format
  const productKey = `product:talos:${version}:${arch}:default`;
  const metadataJson = await env.IMAGE_HASHES.get(productKey);
  
  if (!metadataJson) {
    return new Response(`Product not found for ${repo}/${version}/${arch}. Image may not be available yet.`, { 
      status: 404,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  // Parse metadata to get hash
  let metadata;
  try {
    metadata = JSON.parse(metadataJson);
  } catch (e) {
    return new Response(`Invalid metadata format for ${productKey}`, { 
      status: 500,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  const hash = metadata.hash;
  
  // GitHub releases URL (source of truth)
  const githubUrl = `https://github.com/windsorcli/${repo}/releases/download/${version}/${filename}`;
  const proxyUrl = `${new URL(request.url).protocol}//${new URL(request.url).host}${new URL(request.url).pathname}`;
  
  try {
    const response = await fetch(githubUrl);
    
    if (!response.ok) {
      return new Response(`GitHub error: ${response.status}`, { 
        status: response.status,
        headers: { 'Content-Type': 'text/plain' }
      });
    }
    
    // Clone response headers and add required Incus headers
    const newHeaders = new Headers(response.headers);
    newHeaders.set('Incus-Image-Hash', hash);
    newHeaders.set('Incus-Image-URL', proxyUrl);
    newHeaders.set('Access-Control-Allow-Origin', '*');
    
    // Stream response (don't load entire file into memory)
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

/**
 * Main request handler for the Cloudflare Worker.
 * 
 * Routes requests to appropriate handlers based on path:
 * - /streams/v1/index.json → handleIndex()
 * - /streams/v1/images.json → handleImages()
 * - /{repo}/{version}/{filename} → handleImageDownload()
 * 
 * @type {Object}
 */
export default {
  /**
   * Handles incoming HTTP requests.
   * 
   * @param {Request} request - The incoming HTTP request
   * @param {Object} env - Cloudflare Worker environment with IMAGE_HASHES KV binding
   * @returns {Promise<Response>} HTTP response
   */
  async fetch(request, env) {
    const url = new URL(request.url);
    
        // Simplestream endpoints
        if (url.pathname === '/streams/v1/index.json') {
          return handleIndex(env);
        }
        
        if (url.pathname === '/streams/v1/images.json') {
          return handleImages(env);
        }
    
    // Direct image download (backward compatible)
    const pathMatch = url.pathname.match(/^\/([^\/]+)\/(v[\d.]+)\/(.+)$/);
    if (pathMatch) {
      return handleImageDownload(request, env, pathMatch);
    }
    
    return new Response('Not Found', { status: 404 });
  }
};
