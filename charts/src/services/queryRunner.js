const { spawn } = require('child_process')
const path = require('path')

function execScript(scriptPath, args = []) {
  return new Promise((resolve, reject) => {
    // Ensure we invoke via bash so .sh scripts run correctly
    const proc = spawn('bash', [scriptPath, ...args], { cwd: path.dirname(scriptPath) })

    let stdout = ''
    let stderr = ''
    proc.stdout.on('data', d => { stdout += d.toString() })
    proc.stderr.on('data', d => { stderr += d.toString() })
    proc.on('error', err => reject(err))
    proc.on('close', code => {
      if (code !== 0) return reject(new Error(`script exited ${code}: ${stderr}`))
      resolve(stdout.trim())
    })
  })
}

module.exports = { execScript }
