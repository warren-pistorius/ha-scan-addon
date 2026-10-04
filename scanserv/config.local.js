const { execFile } = require('child_process');

function copyToNas(fileInfo) {
  const share = process.env.SCANSERV_NAS_SHARE;
  const auth = process.env.SCANSERV_NAS_AUTH;
  const dir = process.env.SCANSERV_NAS_PATH || '/';
  if (/["\\]/.test(fileInfo.fullname)) {
    return Promise.reject(new Error(`unsupported characters in file name: ${fileInfo.name}`));
  }
  const args = [share, '-A', auth, '-D', dir, '-c', `put "${fileInfo.fullname}" "${fileInfo.name}"`];
  return new Promise((resolve, reject) => {
    execFile('smbclient', args, { timeout: 120000 }, (err, stdout, stderr) => {
      if (err) {
        const reason = `${stderr}\n${stdout}`.trim().split('\n').filter(Boolean).pop() || err.message;
        reject(new Error(`smbclient exit ${err.code}: ${reason}`));
      } else {
        resolve();
      }
    });
  });
}

module.exports = {
  afterConfig(config) {
    if (process.env.SCANSERV_OUTPUT_DIR) {
      config.outputDirectory = process.env.SCANSERV_OUTPUT_DIR;
    }
    config.log.level = 'INFO';
  },

  async afterScan(fileInfo) {
    if (!process.env.SCANSERV_NAS_SHARE) {
      return;
    }
    // The scan is already saved locally, so a failed copy is logged rather than failing the scan.
    try {
      await copyToNas(fileInfo);
      console.log(`NAS copy ok: ${fileInfo.name}`);
    } catch (e) {
      console.error(`NAS copy failed for ${fileInfo.name}: ${e.message}`);
    }
  }
};
