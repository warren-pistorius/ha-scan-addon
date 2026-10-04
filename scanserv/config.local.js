module.exports = {
  afterConfig(config) {
    if (process.env.SCANSERV_OUTPUT_DIR) {
      config.outputDirectory = process.env.SCANSERV_OUTPUT_DIR;
    }
    config.log.level = 'INFO';
  }
};
