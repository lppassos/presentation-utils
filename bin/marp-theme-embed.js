#!/usr/bin/env node

/*
  Compile a Marp theme CSS into a standalone CSS file by:
  - inlining @import rules (recursively)
  - embedding local url(...) assets as data URIs

  This mirrors the intent of marp-utils.ps1, but runs on Linux in-container.
*/

const fs = require('fs')
const os = require('os')
const path = require('path')

function die(msg) {
  process.stderr.write(String(msg).trimEnd() + '\n')
  process.exit(2)
}

function parseArgs(argv) {
  const out = { input: '' }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--input' || a === '-i') {
      out.input = argv[i + 1] || ''
      i++
    } else if (a === '-h' || a === '--help') {
      out.help = true
    }
  }
  return out
}

function getMimeType(p) {
  const ext = path.extname(p).toLowerCase()
  switch (ext) {
    case '.woff2':
      return 'font/woff2'
    case '.woff':
      return 'font/woff'
    case '.ttf':
      return 'font/ttf'
    case '.otf':
      return 'font/otf'
    case '.eot':
      return 'application/vnd.ms-fontobject'
    case '.svg':
      return 'image/svg+xml'
    case '.png':
      return 'image/png'
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg'
    case '.gif':
      return 'image/gif'
    case '.webp':
      return 'image/webp'
    case '.avif':
      return 'image/avif'
    default:
      return 'application/octet-stream'
  }
}

function fileToDataUri(filePath) {
  const bytes = fs.readFileSync(filePath)
  const b64 = Buffer.from(bytes).toString('base64')
  const mime = getMimeType(filePath)
  return `data:${mime};base64,${b64}`
}

function looksLikeExternalUrl(u) {
  const t = u.trim()
  return /^(data:|https?:|file:|\/\/)/i.test(t)
}

function splitUrlSuffix(rawUrl) {
  const trimmed = rawUrl.trim()
  const q = trimmed.indexOf('?')
  const h = trimmed.indexOf('#')
  let cut = -1
  if (q >= 0 && h >= 0) cut = Math.min(q, h)
  else if (q >= 0) cut = q
  else if (h >= 0) cut = h
  if (cut >= 0) return { base: trimmed.slice(0, cut), suffix: trimmed.slice(cut) }
  return { base: trimmed, suffix: '' }
}

function embedCssUrls(css, baseDir) {
  // Roughly matches url('...'), url("..."), url(...) and ignores closing paren inside url.
  const urlRe = /url\(\s*(?:"([^"]+)"|'([^']+)'|([^\)\s]+))\s*\)/g
  return css.replace(urlRe, (m, q1, q2, q3) => {
    const rawUrl = q1 || q2 || q3 || ''
    if (!rawUrl) return m
    if (looksLikeExternalUrl(rawUrl)) return m

    const { base, suffix } = splitUrlSuffix(rawUrl)
    let candidate = base
    if (!path.isAbsolute(candidate)) candidate = path.join(baseDir, candidate)

    try {
      const resolved = fs.realpathSync(candidate)
      if (!fs.existsSync(resolved)) return m
      const data = fileToDataUri(resolved)
      return `url("${data}${suffix}")`
    } catch {
      return m
    }
  })
}

function inlineCssImports(cssPath, visited) {
  const full = fs.realpathSync(cssPath)
  if (visited.has(full)) return ''
  visited.add(full)

  const baseDir = path.dirname(full)
  let css = fs.readFileSync(full, 'utf8')

  // Matches lines like:
  //   @import "foo.css";
  //   @import url(foo.css) screen and (min-width: 600px);
  const importRe = /^\s*@import\s+(?:url\(\s*)?("([^"]+)"|'([^']+)'|([^\)\s;]+))\s*\)?(\s+[^;]+)?\s*;\s*$/gmi

  css = css.replace(importRe, (m, _wrap, q1, q2, q3, media) => {
    const importPath = (q1 || q2 || q3 || '').trim()
    if (!importPath) return m
    if (looksLikeExternalUrl(importPath)) return m

    let candidate = importPath
    if (!path.isAbsolute(candidate)) candidate = path.join(baseDir, candidate)

    try {
      const resolved = fs.realpathSync(candidate)
      if (!resolved.toLowerCase().endsWith('.css')) return m
      if (!fs.existsSync(resolved)) return m

      const inlined = inlineCssImports(resolved, visited)
      if (!inlined) return ''
      const mediaTrim = (media || '').trim()
      if (mediaTrim) return `@media ${mediaTrim} {\n${inlined}\n}`
      return inlined
    } catch {
      return m
    }
  })

  return embedCssUrls(css, baseDir)
}

function writeTempCss(contents) {
  const name = `marp-theme-${Date.now()}-${Math.random().toString(16).slice(2)}.css`
  const outPath = path.join(os.tmpdir(), name)
  fs.writeFileSync(outPath, contents, 'utf8')
  return outPath
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    process.stdout.write('Usage: marp-theme-embed.js --input <theme.css>\n')
    return
  }
  if (!args.input) die('ERROR: --input is required')
  if (!fs.existsSync(args.input)) die(`ERROR: Theme CSS not found: ${args.input}`)

  const visited = new Set()
  const compiled = inlineCssImports(args.input, visited)
  const outPath = writeTempCss(compiled)
  process.stdout.write(outPath)
}

main()
