const { execSync, spawnSync } = require('child_process');
const fs = require('fs');
const env = require('./env');

/**
 * TAV-X Core UI Components (Universal)
 * Automatically adapts between Gum (TUI) and Standard Text Mode.
 */

const { red, green, yellow, blue, cyan, magenta, bold, nc, gray } = env.colors;

const C_PINK = '\x1b[38;5;212m';
const C_PURPLE = '\x1b[38;5;99m';
const C_DIM = '\x1b[38;5;240m';
const C_CYAN = '\x1b[38;5;36m';

const hasGum = process.env.HAS_GUM === 'true';

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

// Helper for synchronous input reading without dependencies
function readLineSync() {
    const BUF_SIZE = 1024;
    const buf = Buffer.alloc(BUF_SIZE);
    let line = '';
    let fd = 0; // Default to stdin
    let usingTty = false;

    try {
        fd = fs.openSync('/dev/tty', 'rs');
        usingTty = true;
    } catch (e) {
        fd = process.stdin.fd;
    }

    try {
        while (true) {
            const bytesRead = fs.readSync(fd, buf, 0, BUF_SIZE);
            if (bytesRead === 0) {
                // EOF: 输入流已关闭，无法继续交互，必须退出
                console.log('\n[Error] 输入流已断开 (EOF)。');
                process.exit(0); 
            }
            const chunk = buf.toString('utf8', 0, bytesRead);
            line += chunk;
            if (line.includes('\n')) {
                line = line.split('\n')[0];
                break;
            }
        }
    } catch (e) { 
        // 任何读取错误都应终止，防止死循环
        process.exit(1);
    } finally {
        if (usingTty) {
            try { fs.closeSync(fd); } catch(e){}
        }
    }
    return line.replace(/\r/g, '').trim();
}

ui.print = (type, message) => {
    if (hasGum) {
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
        } catch (e) { /* Fallback */ }
    }

    switch (type.toLowerCase()) {
        case 'info': console.log(`${blue}  ℹ ${nc}${message}`); break;
        case 'success': console.log(`${green}  ✔ ${nc}${message}`); break;
        case 'warn': console.log(`${yellow}  ⚠ ${nc}${message}`); break;
        case 'error': console.log(`${red}  ✘ ${nc}${message}`); break;
        default: console.log(message);
    }
};

ui.header = (subtitle = '') => {
    // Clear screen best effort
    process.stdout.write('\x1Bc'); 
    
    if (hasGum) {
        try {
            // Try gum colored logo
             const res = spawnSync('gum', ['style', '--foreground', '212', getAsciiLogo()], { encoding: 'utf8' });
             if (res.status === 0) {
                 console.log(res.stdout);
                 const ver = process.env.CURRENT_VERSION || '3.x';
                 const vTag = spawnSync('gum', ['style', '--foreground', '240', '--align', 'right', `Ver: ${ver} | by Future 404  `], { encoding: 'utf8' });
                 console.log(vTag.stdout);
                 if (subtitle) {
                    const sub = spawnSync('gum', ['style', '--foreground', '99', '--bold', `  🚀 ${subtitle}`], { encoding: 'utf8' });
                    const div = spawnSync('gum', ['style', '--foreground', '240', `  ───────────────────────────────────────`], { encoding: 'utf8' });
                    console.log(sub.stdout);
                    console.log(div.stdout);
                 }
                 console.log('');
                 return;
             }
        } catch (e) {} // ignore
    }

    // Text Mode Header
    console.log(`${C_PINK}${getAsciiLogo()}${nc}`);
    const ver = process.env.CURRENT_VERSION || '3.x';
    const tagText = `Ver: ${ver} | by Future 404`;
    console.log(`${C_DIM}${tagText.padStart(48)}${nc}`);
    console.log(`${gray}----------------------------------------${nc}`);

    if (subtitle) {
        console.log(`${C_PURPLE}${bold}  🚀 ${subtitle}${nc}`);
        console.log(`${gray}----------------------------------------${nc}`);
    }
    console.log('');
};

ui.menu = (title, options) => {
    if (hasGum) {
        try {
            const args = ['choose', '--header', '', '--cursor', '👉 ', '--cursor.foreground', '212', '--selected.foreground', '212', ...options];
            if (title) console.log(`\n${C_CYAN}[ ${title} ]${nc}`);
            const result = spawnSync('gum', args, { stdio: ['inherit', 'pipe', 'inherit'], encoding: 'utf8' });
            if (result.status === 0) return result.stdout.trim();
        } catch (e) { /* Fallback */ }
    }

    // Text Mode Menu
    if (title) console.log(`\n${C_CYAN}[ ${title} ]${nc}`);
    options.forEach((opt, i) => console.log(`  ${yellow}${i + 1}.${nc} ${opt}`));
    
    while(true) {
        process.stdout.write(`\n  ${blue}➜${nc} 请输入编号: `);
        const input = readLineSync();
        const idx = parseInt(input);
        
        if (!isNaN(idx) && idx >= 1 && idx <= options.length) {
            return options[idx - 1];
        }
        console.log(`  ${red}✘ 无效选择，请重试。${nc}`);
    }
};

ui.input = (prompt, defaultValue = '', isPassword = false) => {
    if (hasGum) {
        try {
            const args = ['input', '--placeholder', prompt, '--width', '40', '--cursor.foreground', '212'];
            if (defaultValue) args.push('--value', defaultValue);
            if (isPassword) args.push('--password');
            const result = spawnSync('gum', args, { stdio: ['inherit', 'pipe', 'inherit'], encoding: 'utf8' });
            if (result.status === 0) return result.stdout.trim() || defaultValue;
        } catch (e) { /* Fallback */ }
    }

    // Text Mode Input
    process.stdout.write(`  ${cyan}➜${nc} ${prompt}`);
    if (defaultValue) process.stdout.write(` [${yellow}${defaultValue}${nc}]`);
    process.stdout.write(': ');
    
    const val = readLineSync();
    return val || defaultValue;
};

ui.confirm = (prompt) => {
    if (hasGum) {
        try {
            const result = spawnSync('gum', ['confirm', prompt, '--affirmative', '是', '--negative', '否', '--selected.background', '212'], { stdio: 'inherit' });
            return result.status === 0;
        } catch (e) { /* Fallback */ }
    }

    // Text Mode Confirm
    process.stdout.write(`  ${yellow}⚠ ${prompt} (y/n): ${nc}`);
    const val = readLineSync().toLowerCase();
    return val === 'y' || val === 'yes';
};

ui.pause = () => {
    console.log('');
    if (hasGum) {
        try {
            spawnSync('gum', ['style', '--foreground', '240', '  按任意键继续...'], { stdio: 'inherit' });
            execSync('read -n 1 -s -r', { shell: '/bin/bash', stdio: 'inherit' });
            return;
        } catch (e) {} // ignore
    }

    process.stdout.write(`${gray}  按任意键继续...${nc}`);
    try { 
        // 简单读取一个字符，无需回车（如果在 Bash 下可用 read -n）
        // 在 Node 中比较麻烦，这里简单用 readLineSync 等待回车
        readLineSync(); 
    } catch(e) {} // ignore
};

module.exports = ui;