const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const env = require('../../core/env');
const ui = require('../../core/ui');

/**
 * CLIProxyAPI YAML Configuration Manager (v8 Layout Compatible + yq-free Fallback)
 */

const CP_DIR = env.getAppPath('cliproxyapi');
const CONFIG_FILE = path.join(CP_DIR, 'config.yaml');

function hasYq() {
    try {
        execSync('command -v yq', { stdio: 'ignore' });
        return true;
    } catch (e) {
        return false;
    }
}

function querySectionFieldFallback(section, field) {
    try {
        const content = fs.readFileSync(CONFIG_FILE, 'utf8');
        const lines = content.split(/\r?\n/);
        let inSection = false;
        let sectionIndent = -1;

        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            const indent = line.search(/\S/);

            if (!inSection) {
                const secMatch = line.match(/^(\s*)([a-zA-Z0-9_-]+):\s*(?:#.*)?$/);
                if (secMatch && secMatch[2] === section) {
                    inSection = true;
                    sectionIndent = indent;
                }
            } else {
                if (indent <= sectionIndent) {
                    inSection = false;
                    const secMatch = line.match(/^(\s*)([a-zA-Z0-9_-]+):\s*(?:#.*)?$/);
                    if (secMatch && secMatch[2] === section) {
                        inSection = true;
                        sectionIndent = indent;
                    }
                    continue;
                }
                const fieldRegex = new RegExp(`^\\s*${field}:\\s*(.*?)(?:\\s+#.*)?$`);
                const m = line.match(fieldRegex);
                if (m) {
                    let val = m[1].trim();
                    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
                        val = val.slice(1, -1);
                    }
                    return val;
                }
            }
        }
    } catch (e) {}
    return null;
}

function updateSectionFieldFallback(section, field, value) {
    try {
        const content = fs.readFileSync(CONFIG_FILE, 'utf8');
        const lines = content.split(/\r?\n/);
        let inSection = false;
        let sectionIndent = -1;
        let updated = false;

        const formattedValue = typeof value === 'string' ? `"${value}"` : String(value);

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) continue;
            const indent = line.search(/\S/);

            if (!inSection) {
                const secMatch = line.match(/^(\s*)([a-zA-Z0-9_-]+):\s*(?:#.*)?$/);
                if (secMatch && secMatch[2] === section) {
                    inSection = true;
                    sectionIndent = indent;
                }
            } else {
                if (indent <= sectionIndent) {
                    inSection = false;
                    const secMatch = line.match(/^(\s*)([a-zA-Z0-9_-]+):\s*(?:#.*)?$/);
                    if (secMatch && secMatch[2] === section) {
                        inSection = true;
                        sectionIndent = indent;
                    }
                    continue;
                }
                const fieldRegex = new RegExp(`^(\\s*${field}:\\s*)(.*?)(\\s+#.*)?$`);
                const m = line.match(fieldRegex);
                if (m) {
                    const comment = m[3] || '';
                    lines[i] = `${m[1]}${formattedValue}${comment}`;
                    updated = true;
                    break;
                }
            }
        }

        if (updated) {
            fs.writeFileSync(CONFIG_FILE, lines.join('\n'), 'utf8');
            return true;
        }
    } catch (e) {}
    return false;
}

function queryConfig(item) {
    if (hasYq()) {
        try {
            const cmd = `yq '${item.key}' '${CONFIG_FILE}'`;
            const out = execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
            if (out !== '' && out !== 'null') return out.replace(/^"(.*)"$/, '$1');
        } catch (e) {}
    }
    return querySectionFieldFallback(item.section, item.field);
}

function updateConfig(item, value) {
    // 优先使用保留注释的块级精准替换，失败时再用 yq
    if (updateSectionFieldFallback(item.section, item.field, value)) {
        return true;
    }
    if (hasYq()) {
        try {
            let formattedValue = value;
            if (typeof value === 'string') {
                formattedValue = `"${value}"`;
            }
            const cmd = `yq -i '${item.key} = ${formattedValue}' '${CONFIG_FILE}'`;
            execSync(cmd);
            return true;
        } catch (e) {}
    }
    ui.print('error', `无法更新配置: ${item.key}`);
    return false;
}

const schema = [
    { key: '.server.port', section: 'server', field: 'port', type: 'int', label: '服务端口', desc: '程序监听的端口，默认 8317' },
    { key: '.server.host', section: 'server', field: 'host', type: 'str', label: '监听地址', desc: '"" 表示绑定所有接口，"127.0.0.1" 仅限本机' },
    { key: '.management.allow-remote', section: 'management', field: 'allow-remote', type: 'bool', label: '允许远程管理', desc: '开启后可从非本机 IP 访问管理后台' },
    { key: '.management.secret-key', section: 'management', field: 'secret-key', type: 'str', label: '管理密钥', desc: '管理后台的登录凭证 (输入明文后程序启动会自动哈希)' },
    { key: '.management.disable-control-panel', section: 'management', field: 'disable-control-panel', type: 'bool', label: '禁用控制面板', desc: '是否关闭自带的 WebUI 界面' },
    { key: '.observability.logs.debug', section: 'logs', field: 'debug', type: 'bool', label: '调试模式', desc: '开启后会输出更详细的日志' },
    { key: '.requests.proxy-url', section: 'requests', field: 'proxy-url', type: 'str', label: '上级代理', desc: '例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:1080' }
];

function configMenu() {
    if (!fs.existsSync(CONFIG_FILE)) {
        ui.print('error', '配置文件不存在，请先安装应用。');
        ui.pause();
        return;
    }

    while (true) {
        ui.header('CLIProxyAPI 可视化配置 (v8)');
        
        const menuOpts = schema.map(item => {
            const val = queryConfig(item);
            let displayVal = (val === null || val === 'null') ? '(未设置)' : val;
            let icon = '✏️ ';
            
            if (item.type === 'bool') {
                const isTrue = val === 'true';
                icon = isTrue ? '🟢' : '🔴';
                displayVal = isTrue ? '[开启]' : '[关闭]';
            } else {
                displayVal = `[${displayVal}]`;
            }
            
            return `${icon} ${item.label} ${displayVal}`;
        });
        
        menuOpts.push('🔙 返回面板');
        
        const choice = ui.menu('选择要修改的项', menuOpts);
        if (!choice || choice.includes('返回')) break;
        
        const idx = menuOpts.indexOf(choice);
        const item = schema[idx];
        
        console.log(`\n配置项: ${item.label}`);
        console.log(`说明: ${item.desc}\n`);
        
        const curVal = queryConfig(item);
        
        if (item.type === 'bool') {
            const nextVal = !(curVal === 'true');
            if (updateConfig(item, nextVal)) {
                ui.print('success', `已切换为: ${nextVal ? '开启' : '关闭'}`);
            }
        } else {
            let promptVal = (curVal === null || curVal === 'null') ? '' : curVal;
            const input = ui.input(`请输入 ${item.label}`, promptVal);
            
            if (input !== null) {
                let finalVal = input;
                if (item.type === 'int') {
                    finalVal = parseInt(input);
                    if (isNaN(finalVal)) {
                        ui.print('error', '必须输入数字');
                        ui.pause();
                        continue;
                    }
                }
                
                if (updateConfig(item, finalVal)) {
                    ui.print('success', '配置已更新');
                }
            }
        }
        ui.pause();
    }
}

configMenu();
