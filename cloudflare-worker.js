/**
 * Cloudflare Worker for Incus simplestreams image server
 * 
 * Implements simplestream protocol for Incus image server.
 * 
 * Supports:
 * - /streams/v1/index.json - Lists available products (simplestreams index)
 * - /streams/v1/images.json - Full product metadata (simplestreams images)
 * - /images/{product}/{version}/{arch}/{variant}/{versionKey}/{filename} - Direct image download with Incus headers
 * 
 * Configuration:
 * - GITHUB_ORG: GitHub organization name (default: 'windsorcli')
 * - Can be overridden via Cloudflare Worker environment variables
 * 
 * @module cloudflare-worker
 */

// Configuration - can be overridden via Cloudflare Worker environment variables
const CONFIG = {
  // GitHub organization name (e.g., 'windsorcli', 'myorg')
  GITHUB_ORG: 'windsorcli',
};

/**
 * Retrieves the list of all product keys from Cloudflare KV.
 * 
 * Product keys follow the format: product:{os}:{version}:{arch}:{variant}
 * Example: product:talos:v1.12.0:amd64:default
 *          product:alpine:v3.19:amd64:default (future)
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
    // KV key format: product:{os}:{version}:{arch}:{variant}
    // Simplestreams key format: {os}:{version}:{arch}:{variant} (no "product:" prefix)
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
            aliases: `${os}/${version}/${arch}/${variant},${os}/${version}/${arch},${os}/${version}`,
            arch: arch,
            os: os.charAt(0).toUpperCase() + os.slice(1),
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
        
        // Paths are relative to the simplestreams base URL
        // Incus will construct the full URL: {baseUrl}/{path}
        // Match official format: images/{os}/{release}/{arch}/{variant}/{version_key}/{file}
        // Use 'os' (product name) from KV key, not hardcoded 'talos'
        const metaPath = `images/${os}/${version}/${arch}/${variant}/${versionKey}/incus.tar.xz`;
        const diskPath = `images/${os}/${version}/${arch}/${variant}/${versionKey}/disk.qcow2`;

        // For split format
        // - incus.tar.xz: metadata file (small, ~1KB)
        // - disk.qcow2: disk file (large, ~197MB) - key is 'disk.qcow2', ftype is 'disk-kvm.img'
        // - combined_disk-kvm-img_sha256: hash of concatenated metadata + disk (for fingerprint)
        images[simplestreamsKey].versions[versionKey] = {
          items: {
            // Metadata file - small tarball with metadata.yaml only
            'incus.tar.xz': {
              ftype: 'incus.tar.xz',
              sha256: metadata.meta_hash,
              size: metadata.meta_size,
              path: metaPath,
              // Combined hash for VM images (concatenated metadata + disk)
              // Property name is 'combined_disk-kvm-img_sha256' (official format)
              // This is used as the image fingerprint by Incus
              'combined_disk-kvm-img_sha256': metadata.combined_hash
            },
            // Disk file - qcow2 disk image
            // Key must be 'disk.qcow2' to match official simplestreams format
            'disk.qcow2': {
              ftype: 'disk-kvm.img',
              sha256: metadata.disk_hash,
              size: metadata.disk_size,
              path: diskPath
            },
            // LXD compatibility (alias to incus.tar.xz)
            'lxd.tar.xz': {
              ftype: 'lxd.tar.xz',
              sha256: metadata.meta_hash,
              size: metadata.meta_size,
              path: metaPath,
              'combined_disk-kvm-img_sha256': metadata.combined_hash
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
  
  // Convert KV product keys (product:{os}:...) to simplestreams format ({os}:...)
  const simplestreamsProducts = kvProducts.map(kvKey => {
    const parts = kvKey.split(':');
    if (parts.length === 5 && parts[0] === 'product') {
      // Remove "product:" prefix: product:{os}:v1.12.0:amd64:default -> {os}:v1.12.0:amd64:default
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
  
  // Use compact JSON (no pretty-printing) to match official format exactly
  return new Response(JSON.stringify(index), {
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
  
  // Use compact JSON (no pretty-printing) to match official format exactly
  return new Response(JSON.stringify(images), {
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*'
    }
  });
}

/**
 * Handles simplestreams image download requests.
 * 
 * Proxies requests to appropriate sources and adds required Incus headers:
 * - Metadata files (incus.tar.xz): GitHub Releases
 * - Disk files (disk.qcow2): Talos image factory (https://factory.talos.dev)
 * - Incus-Image-Hash: SHA256 hash of the image file
 * - Incus-Image-URL: URL where the image is being served from
 * 
 * Path format: /images/{product}/{version}/{arch}/{variant}/{versionKey}/{filename}
 * Example: /images/talos/v1.12.0/amd64/default/20251226_04:25/incus.tar.xz
 *          /images/talos/v1.12.0/amd64/default/20251226_04:25/disk.qcow2
 * 
 * @param {Request} request - The incoming HTTP request
 * @param {Object} env - Cloudflare Worker environment with IMAGE_HASHES KV binding
 * @returns {Promise<Response>} Streaming response with image data and Incus headers
 */
async function handleImageDownload(request, env) {
  const url = new URL(request.url);
  
  // Simplestreams path format: /images/{product}/{version}/{arch}/{variant}/{versionKey}/{filename}
  // Examples:
  //   /images/talos/v1.12.0/amd64/default/20251226_05:39/incus.tar.xz (metadata)
  //   /images/talos/v1.12.0/amd64/default/20251226_05:39/disk.qcow2 (disk)
  //   /images/alpine/v3.19/amd64/default/20251226_05:39/incus.tar.xz (future)
  //   /images/alpine/v3.19/amd64/default/20251226_05:39/incus.tar.xz (future)
  const simplestreamsMatch = url.pathname.match(/^\/images\/([^\/]+)\/([^\/]+)\/([^\/]+)\/([^\/]+)\/([^\/]+)\/(.+)$/);
  
  if (!simplestreamsMatch) {
    return new Response('Invalid path format. Expected: /images/{product}/{version}/{arch}/{variant}/{versionKey}/{filename}', { 
      status: 400,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  const [, product, version, arch, variant, versionKey, filename] = simplestreamsMatch;
  
  // Normalize architecture names to Incus standard
  const archMap = {
    'aarch64': 'arm64',
    'arm64': 'arm64',
    'x86_64': 'amd64',
    'x64': 'amd64',
    'amd64': 'amd64',
  };
  const normalizedArch = archMap[arch.toLowerCase()] || arch;
  
  // Get metadata from KV using unified product key format
  const productKey = `product:${product}:${version}:${normalizedArch}:${variant}`;
  const metadataJson = await env.IMAGE_HASHES.get(productKey);
  
  if (!metadataJson) {
    return new Response(`Product not found for ${product}/${version}/${normalizedArch}/${variant}. Image may not be available yet.`, { 
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
  
  // Determine which file is being requested and get appropriate hash
  let hash;
  let sourceUrl;
  
  if (filename === 'incus.tar.xz' || filename === 'lxd.tar.xz') {
    // Metadata file - still served from GitHub releases
    hash = metadata.meta_hash;
    const githubOrg = env.GITHUB_ORG || CONFIG.GITHUB_ORG;
    const githubRepo = metadata.github_repo || product;
    const filenamePrefix = metadata.filename_prefix || product;
    const githubFilename = `${filenamePrefix}-${normalizedArch}-incus.tar.xz`;
    sourceUrl = `https://github.com/${githubOrg}/${githubRepo}/releases/download/${version}/${githubFilename}`;
  } else if (filename === 'disk.qcow2' || filename === 'disk-kvm.img') {
    // Disk file - proxy to Talos image factory
    hash = metadata.disk_hash;
    // Use Talos factory URL from metadata, or construct default pattern
    // Default pattern: https://factory.talos.dev/image/{schematic_id}/{version}/metal-{arch}.qcow2
    // Default schematic ID for vanilla Talos: 376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba
    if (metadata.talos_factory_url) {
      sourceUrl = metadata.talos_factory_url;
    } else {
      // Default Talos image factory URL pattern
      const schematicId = metadata.talos_schematic_id || '376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba';
      // Version can be with or without 'v' prefix
      const factoryVersion = version.startsWith('v') ? version : `v${version}`;
      sourceUrl = `https://factory.talos.dev/image/${schematicId}/${factoryVersion}/metal-${normalizedArch}.qcow2`;
    }
  } else {
    return new Response(`Unknown file: ${filename}. Expected incus.tar.xz, lxd.tar.xz, or disk.qcow2`, { 
      status: 400,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  const proxyUrl = `${new URL(request.url).protocol}//${new URL(request.url).host}${new URL(request.url).pathname}`;
  
  try {
    const response = await fetch(sourceUrl);
    
    if (!response.ok) {
      return new Response(`Upstream error: ${response.status}`, { 
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
 * - /images/{product}/{version}/{arch}/{variant}/{versionKey}/{filename} → handleImageDownload()
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
    
    // Simplestreams image download
    // Simplestreams image download path (generic - supports any product)
    // Path format: /images/{product}/{version}/{arch}/{variant}/{versionKey}/{filename}
    if (url.pathname.match(/^\/images\/[^\/]+\//)) {
      return handleImageDownload(request, env);
    }
    
    return new Response('Not Found', { status: 404 });
  }
};
