const { execSync, spawnSync } = require('child_process');
const env = require('./env');

/**
 * TAV-X Core UI Components
 * Wraps gum and ANSI codes for a consistent CLI experience.
 */

const { red, green, yellow, blue, cyan, magenta, bold, nc, gray, white } = env.colors;

const C_PINK = '\x1b[38;5;212m';
const C_PURPLE = '\x1b[38;5;99m';
const C_DIM = '\x1b[38;5;240m';
const C_CYAN = '\x1b[38;5;36m';

const ui = {};

function getAsciiLogo() {
    return `
████████╗░█████╗░██╗░░░██╗	██╗░░██╗
╚══██╔══╝██╔══██╗██║░░░██║	╚██╗██╔╝
░░░██║░░░███████║╚██╗░██╔╝	░╚███╔╝░
░░░██║░░░██╔══██║░╚████╔╝░	░██╔██╗░
░░░██║░░░██║░░██║░░╚██╔╝░░	██╔╝╚██╗
░░░╚═╝░░░╚═╝░░╚═╝░░░╚═╝░░░	╚═╝░░╚═╝
                T A V   X`;
}

ui.print = (type, message) => {
    try {
        let args = ['style'];
        switch (type.toLowerCase()) {
            case 'success': args.push('--foreground', '82', `  ✔ ${message}`); break;
            case 'error':   args.push('--foreground', '196', `  ✘ ${message}`); break;
            case 'warn':    args.push('--foreground', '220', `  ⚠ ${message}`); break;
            default:        args.push('--foreground', '99', `  ℹ ${message}`); break;
        }
        const res = spawnSync('gum', args, { encoding: 'utf8' });
        if (res.status === 0) {
            console.log(res.stdout.trim());
            return;
        }
    } catch (e) { /* ignore and fallback */ }

    switch (type.toLowerCase()) {
        case 'info': console.log(`${blue}  ℹ ${nc}${message}`); break;
        case 'success': console.log(`${green}  ✔ ${nc}${message}`); break;
        case 'warn': console.log(`${yellow}  ⚠ ${nc}${message}`); break;
        case 'error': console.log(`${red}  ✘ ${nc}${message}`); break;
        default: console.log(message);
    }
};

ui.header = (subtitle = '') => {
    process.stdout.write('\x1Bc');
    console.log(`${C_PINK}${getAsciiLogo()}${nc}`);
    const ver = process.env.CURRENT_VERSION || '3.1.0';
    const tagText = `Ver: ${ver} | by Future 404`;
    const cols = 48; 
    const padLen = Math.max(0, cols - tagText.length);
    const pad = ' '.repeat(padLen);
    console.log(`${C_DIM}${pad}${tagText}${nc}`);

    if (subtitle) {
        const prefix = `  🚀 `;
        const divider = `  ───────────────────────────────────────`;
        console.log(`${C_PURPLE}${bold}${prefix}${nc}${subtitle}`);
        console.log(`${C_DIM}${divider}${nc}`);
    }
    console.log('');
};

ui.menu = (title, options) => {
    try {
        const args = ['choose', '--header', '', '--cursor', '👉 ', '--cursor.foreground', '212', '--selected.foreground', '212', ...options];
        if (title) console.log(`\n${C_CYAN}[ ${title} ]${nc}`);
        
        const result = spawnSync('gum', args, { stdio: ['inherit', 'pipe', 'inherit'], encoding: 'utf8' });
        
        if (result.status !== 0) return null;
        return result.stdout.trim();
    } catch (e) {
        console.log(`\n--- ${title} ---`);
        options.forEach((opt, i) => console.log(`${i + 1}. ${opt}`));
        return null; 
    }
};

ui.input = (prompt, defaultValue = '', isPassword = false) => {
    try {
        const args = ['input', '--placeholder', prompt, '--width', '40', '--cursor.foreground', '212'];
        if (defaultValue) args.push('--value', defaultValue);
        if (isPassword) args.push('--password');
        
        const result = spawnSync('gum', args, { stdio: ['inherit', 'pipe', 'inherit'], encoding: 'utf8' });
        
        if (result.status !== 0) return defaultValue;
        return result.stdout.trim() || defaultValue;
    } catch (e) {
        return defaultValue;
    }
};

ui.confirm = (prompt) => {
    try {
        const result = spawnSync('gum', ['confirm', prompt, '--affirmative', '是', '--negative', '否', '--selected.background', '212'], { stdio: 'inherit' });
        return result.status === 0;
    } catch (e) {
        return false;
    }
};

ui.pause = () => {
    console.log('');
    try {
        spawnSync('gum', ['style', '--foreground', '240', '  按任意键继续...'], { stdio: 'inherit' });
        execSync('read -n 1 -s -r', { shell: '/bin/bash', stdio: 'inherit' });
    } catch (e) {
        console.log(`${gray}  按任意键继续...${nc}`);
        try { execSync('read _', { shell: '/bin/bash', stdio: 'inherit' }); } catch(ex){}
    }
};

module.exports = ui;
