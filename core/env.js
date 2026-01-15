const path = require('path');
const fs = require('fs');

/**
 * TAV-X Core Environment Manager
 */

const env = {};

env.IS_TERMUX = !!process.env.TERMUX_VERSION;
env.OS_TYPE = env.IS_TERMUX ? 'TERMUX' : 'LINUX';

env.TAVX_DIR = process.env.TAVX_DIR || path.resolve(__dirname, '..');
env.TAVX_ROOT = env.TAVX_DIR;

env.CONFIG_DIR = path.join(env.TAVX_DIR, 'config');
env.LOGS_DIR = path.join(env.TAVX_DIR, 'logs');
env.RUN_DIR = path.join(env.TAVX_DIR, 'run');
env.APPS_DIR = process.env.APPS_DIR || path.join(process.env.HOME, 'tav_apps');
env.TAVX_BIN = path.join(env.TAVX_DIR, 'bin');
env.colors = {
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m',
    white: '\x1b[37m',
    gray: '\x1b[90m',
    bold: '\x1b[1m',
    nc: '\x1b[0m'
};

env.getAppPath = (id) => {
    if (id === 'sillytavern') return path.join(process.env.HOME, 'SillyTavern');
    return path.join(env.APPS_DIR, id);
};

env.getProxy = () => {
    const networkConf = path.join(env.CONFIG_DIR, 'network.conf');
    if (fs.existsSync(networkConf)) {
        const content = fs.readFileSync(networkConf, 'utf8').trim();
        if (content.startsWith('PROXY|')) {
            return content.split('|')[1];
        }
    }
    return process.env.http_proxy || null;
};

module.exports = env;
