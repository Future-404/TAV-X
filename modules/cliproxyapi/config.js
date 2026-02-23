const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const env = require('../../core/env');
const ui = require('../../core/ui');

/**
 * CLIProxyAPI YAML Configuration Manager
 */

const CP_DIR = env.getAppPath('cliproxyapi');
const CONFIG_FILE = path.join(CP_DIR, 'config.yaml');

function queryYq(path) {
    try {
        const cmd = `yq '${path}' '${CONFIG_FILE}'`;
        return execSync(cmd, { encoding: 'utf8' }).trim();
    } catch (e) {
        return null;
    }
}

function updateYq(path, value) {
    try {
        // 处理不同类型的值
        let formattedValue = value;
        if (typeof value === 'string') {
            formattedValue = `"${value}"`;
        }
        
        const cmd = `yq -i '${path} = ${formattedValue}' '${CONFIG_FILE}'`;
        execSync(cmd);
        return true;
    } catch (e) {
        ui.print('error', `无法更新配置: ${path}`);
        return false;
    }
}

const schema = [
    { key: '.port', type: 'int', label: '服务端口', desc: '程序监听的端口，默认 8317' },
    { key: '.host', type: 'str', label: '监听地址', desc: '"" 表示绑定所有接口，"127.0.0.1" 仅限本机' },
    { key: '.remote-management.allow-remote', type: 'bool', label: '允许远程管理', desc: '开启后可从非本机 IP 访问管理后台' },
    { key: '.remote-management.secret-key', type: 'str', label: '管理密钥', desc: '管理后台的登录凭证 (输入明文会自动哈希)' },
    { key: '.remote-management.disable-control-panel', type: 'bool', label: '禁用控制面板', desc: '是否关闭自带的 WebUI 界面' },
    { key: '.debug', type: 'bool', label: '调试模式', desc: '开启后会输出更详细的日志' },
    { key: '.proxy-url', type: 'str', label: '上级代理', desc: '例如 socks5://127.0.0.1:1080' }
];

function configMenu() {
    if (!fs.existsSync(CONFIG_FILE)) {
        ui.print('error', '配置文件不存在，请先安装应用。');
        ui.pause();
        return;
    }

    while (true) {
        ui.header('CLIProxyAPI 可视化配置');
        
        const menuOpts = schema.map(item => {
            const val = queryYq(item.key);
            let displayVal = val === 'null' ? '(未设置)' : val;
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
        
        console.log(`
配置项: ${item.label}`);
        console.log(`说明: ${item.desc}
`);
        
        const curVal = queryYq(item.key);
        
        if (item.type === 'bool') {
            const nextVal = !(curVal === 'true');
            if (updateYq(item.key, nextVal)) {
                ui.print('success', `已切换为: ${nextVal ? '开启' : '关闭'}`);
            }
        } else {
            let promptVal = curVal === 'null' ? '' : curVal;
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
                
                if (updateYq(item.key, finalVal)) {
                    ui.print('success', '配置已更新');
                }
            }
        }
        ui.pause();
    }
}

configMenu();
