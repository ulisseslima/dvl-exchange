// Lightweight CLI color helpers
//
// Exports:
//  - styles: mapping of named ANSI sequences
//  - wrap(colorOrSpec, text): returns colored string
//  - printf(colorOrSpec, ...args): console.log where first arg is colored
//  - convenience helpers: gray, yellow, magentaWhite, cyanRed, cyanBlue,
//    blackWhite, greenWhite, blueWhite, opSaved, dividendSaved, loanSaved
//
const styles = {
  Reset: "\x1b[0m",
  Bright: "\x1b[1m",
  Dim: "\x1b[2m",
  Underscore: "\x1b[4m",
  Blink: "\x1b[5m",
  Reverse: "\x1b[7m",
  Hidden: "\x1b[8m",

  FgBlack: "\x1b[30m",
  FgRed: "\x1b[31m",
  FgGreen: "\x1b[32m",
  FgYellow: "\x1b[33m",
  FgBlue: "\x1b[34m",
  FgMagenta: "\x1b[35m",
  FgCyan: "\x1b[36m",
  FgWhite: "\x1b[37m",
  FgGray: "\x1b[90m",

  BgBlack: "\x1b[40m",
  BgRed: "\x1b[41m",
  BgGreen: "\x1b[42m",
  BgYellow: "\x1b[43m",
  BgBlue: "\x1b[44m",
  BgMagenta: "\x1b[45m",
  BgCyan: "\x1b[46m",
  BgWhite: "\x1b[47m",
  BgGray: "\x1b[100m",
}

function _capitalize(word) {
  if (!word) return ''
  word = String(word)
  return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
}

function _normalizeKey(value, kind /* 'fg'|'bg' */) {
  if (!value) return null
  if (styles[value]) return value
  const s = String(value).replace(/^fg|^Fg|^FG|^bg|^Bg|^BG/, '')
  const candidate = (kind === 'fg' ? 'Fg' : 'Bg') + _capitalize(s)
  return styles[candidate] ? candidate : null
}

/**
 * Wrap text with ANSI escapes.
 * colorOrSpec can be:
 *  - 'FgRed' / 'BgBlue' (exact keys)
 *  - 'red' / 'blue' (short names)
 *  - { fg: 'red'|'FgRed', bg: 'blue'|'BgBlue' }
 */
function wrap(colorOrSpec, text) {
  if (typeof colorOrSpec === 'object') {
    const fgKey = _normalizeKey(colorOrSpec.fg, 'fg')
    const bgKey = _normalizeKey(colorOrSpec.bg, 'bg')
    const seq = `${styles[bgKey] || ''}${styles[fgKey] || ''}`
    return `${seq}${text}${styles.Reset}`
  }
  const key = _normalizeKey(colorOrSpec, 'fg') || colorOrSpec
  return `${styles[key] || ''}${text}${styles.Reset}`
}

/**
 * printf with a flexible color spec. If colorOrSpec is an object it may
 * contain {fg, bg} and both will be applied. The first arg is colored,
 * remaining args are printed after the reset.
 */
function printf(colorOrSpec, ...args) {
  if (typeof colorOrSpec === 'object') {
    const fgKey = _normalizeKey(colorOrSpec.fg, 'fg')
    const bgKey = _normalizeKey(colorOrSpec.bg, 'bg')
    const seq = `${styles[bgKey] || ''}${styles[fgKey] || ''}`
    const first = args.shift()
    console.log(`${seq}${first}${styles.Reset}`, ...args)
    return
  }

  const key = styles[colorOrSpec] ? colorOrSpec : _normalizeKey(colorOrSpec, 'fg')
  if (key && args.length) {
    const first = args.shift()
    console.log(`${styles[key]}${first}${styles.Reset}`, ...args)
    return
  }

  console.log(colorOrSpec, ...args)
}

// Convenience wrappers for process-sync-cei.js patterns
function gray(...args) { printf('FgGray', ...args) }
function yellow(...args) { printf('FgYellow', ...args) }
function magentaWhite(...args) { printf({ fg: 'FgWhite', bg: 'BgMagenta' }, ...args) }
function cyanRed(...args) { printf({ fg: 'FgRed', bg: 'BgCyan' }, ...args) }
function cyanBlue(...args) { printf({ fg: 'FgBlue', bg: 'BgCyan' }, ...args) }
function blackWhite(...args) { printf({ fg: 'FgWhite', bg: 'BgBlack' }, ...args) }
function greenWhite(...args) { printf({ fg: 'FgWhite', bg: 'BgGreen' }, ...args) }
function blueWhite(...args) { printf({ fg: 'FgWhite', bg: 'BgBlue' }, ...args) }

// Semantic aliases
function opSaved(...args) { blackWhite(...args) }
function dividendSaved(...args) { greenWhite(...args) }
function loanSaved(...args) { blueWhite(...args) }

module.exports = {
  styles,
  wrap,
  printf,
  gray,
  yellow,
  magentaWhite,
  cyanRed,
  cyanBlue,
  blackWhite,
  greenWhite,
  blueWhite,
  opSaved,
  dividendSaved,
  loanSaved,
}
