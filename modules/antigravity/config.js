const fs = require('fs');
const path = require('path');
const env = require('../../core/env');
const ui = require('../../core/ui');

/**
 * Antigravity Configuration Manager
 */

const AG_DIR = env.getAppPath('antigravity');
const CONFIG_FILE = path.join(AG_DIR, 'config.json');
const ENV_FILE = path.join(AG_DIR, '.env');

function loadJson() {
    try {
        if (!fs.existsSync(CONFIG_FILE)) return {};
        return JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    } catch (e) {
        ui.print('error', '无法读取 config.json');
        return {};
    }
}

function saveJson(data) {
    try {
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(data, null, 2), 'utf8');
        return true;
    } catch (e) {
        ui.print('error', '无法保存 config.json');
        return false;
    }
}

function loadEnv() {
    try {
        if (!fs.existsSync(ENV_FILE)) return {};
        const content = fs.readFileSync(ENV_FILE, 'utf8');
        const envObj = {};
        content.split('\n').forEach(line => {
            line = line.trim();
            if (!line || line.startsWith('#')) return;
            const idx = line.indexOf('=');
            if (idx !== -1) {
                const key = line.substring(0, idx).trim();
                let val = line.substring(idx + 1).trim();
                if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'" ) && val.endsWith("'"))) {
                    val = val.slice(1, -1);
                }
                envObj[key] = val;
            }
        });
        return envObj;
    } catch (e) {
        ui.print('error', '无法读取 .env');
        return {};
    }
}

function saveEnv(data) {
    try {
        let content = fs.existsSync(ENV_FILE) ? fs.readFileSync(ENV_FILE, 'utf8') : '';
        const lines = content.split('\n');
        const newLines = [];
        const processedKeys = new Set();

        lines.forEach(line => {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#')) {
                newLines.push(line);
                return;
            }
            const idx = line.indexOf('=');
            if (idx !== -1) {
                const key = line.substring(0, idx).trim();
                if (data.hasOwnProperty(key)) {
                    newLines.push(`${key}=${data[key]}`);
                    processedKeys.add(key);
                } else {
                    newLines.push(line);
                    if (data[key] !== undefined) processedKeys.add(key);
                }
            } else {
                newLines.push(line);
            }
        });

        for (const key in data) {
            if (!processedKeys.has(key)) {
                newLines.push(`${key}=${data[key]}`);
            }
        }

        fs.writeFileSync(ENV_FILE, newLines.join('\n'), 'utf8');
        return true;
    } catch (e) {
        ui.print('error', '无法保存 .env');
        return false;
    }
}

function getNestedValue(obj, path) {
    return path.split('.').reduce((prev, curr) => (prev ? prev[curr] : undefined), obj);
}

function setNestedValue(obj, path, value) {
    const keys = path.split('.');
    const lastKey = keys.pop();
    const target = keys.reduce((prev, curr) => {
        if (!prev[curr]) prev[curr] = {};
        return prev[curr];
    }, obj);
    target[lastKey] = value;
}

const schemas = {
    server: [
        { key: 'server.port', type: 'int', label: '服务端口', desc: '默认为 8045', file: 'json' },
        { key: 'server.host', type: 'str', label: '监听地址', desc: '0.0.0.0 允许外网访问', file: 'json' },
        { key: 'server.heartbeatInterval', type: 'int', label: '心跳间隔 (ms)', desc: '防止 Cloudflare 断连', file: 'json' },
        { key: 'server.memoryThreshold', type: 'int', label: '内存阈值 (MB)', desc: '超过此值触发 GC', file: 'json' }
    ],
    security: [
        { key: 'API_KEY', type: 'str', label: 'API 密钥', desc: '客户端连接时需要的 Bearer Token', file: 'env' },
        { key: 'ADMIN_USERNAME', type: 'str', label: '管理员账号', desc: '登录管理后台的用户名', file: 'env' },
        { key: 'ADMIN_PASSWORD', type: 'str', label: '管理员密码', desc: '登录管理后台的密码', file: 'env' },
        { key: 'JWT_SECRET', type: 'str', label: 'JWT 密钥', desc: '用于加密 Token 的密钥', file: 'env' }
    ],
    proxy: [
        { key: 'PROXY', type: 'str', label: '代理地址', desc: '例如 http://127.0.0.1:7890', file: 'env' },
        { key: 'IMAGE_BASE_URL', type: 'str', label: '图片 Base URL', desc: '生成的图片访问地址前缀', file: 'env' }
    ],
    defaults: [
        { key: 'defaults.temperature', type: 'float', label: '默认温度', desc: '0.0 - 2.0', file: 'json' },
        { key: 'defaults.topP', type: 'float', label: 'Top P', desc: '0.0 - 1.0', file: 'json' },
        { key: 'defaults.topK', type: 'int', label: 'Top K', desc: '采样数量', file: 'json' },
        { key: 'defaults.maxTokens', type: 'int', label: '最大输出 Token', desc: '单次回答的最大长度限制', file: 'json' },
        { key: 'defaults.thinkingBudget', type: 'int', label: '思考预算', desc: 'Thinking 模型预算 Token', file: 'json' }
    ],
    rotation: [
        { key: 'rotation.strategy', type: 'select', label: '轮询策略', desc: '账号切换逻辑: \n- round_robin: 均衡负载, 每次请求切换账号\n- quota_exhausted: 性能优先, 额度耗尽才切换 (推荐)\n- request_count: 计数切换, 每个账号用满指定次数后切换', options: ['round_robin', 'quota_exhausted', 'request_count'], file: 'json' },
        { key: 'rotation.requestCount', type: 'int', label: '轮询请求数', desc: 'Request Count 模式下切换阈值', file: 'json' }
    ],
    advanced: [
        { key: 'other.passSignatureToClient', type: 'bool', label: '透传签名', desc: '是否将 thoughtSignature 透传给客户端', file: 'json' },
        { key: 'other.useContextSystemPrompt', type: 'bool', label: '合并 System Prompt', desc: '将 System 消息合并到 SystemInstruction', file: 'json' },
        { key: 'SYSTEM_INSTRUCTION', type: 'str', label: '系统提示词', desc: '全局系统级提示词', file: 'env' }
    ]
};

function renderCategory(title, items) {
    while (true) {
        ui.header(`Antigravity 配置 - ${title}`);
        
        const jsonConfig = loadJson();
        const envConfig = loadEnv();
        
        const menuOpts = items.map(item => {
            let val;
            if (item.file === 'json') {
                val = getNestedValue(jsonConfig, item.key);
            } else {
                val = envConfig[item.key];
            }
            if (val === undefined) val = '(未设置)';
            
            let icon = '✏️ ';
            let status = `[${val}]`;
            
            if (item.type === 'bool') {
                const isTrue = val === true || val === 'true';
                icon = isTrue ? '🟢' : '🔴';
                status = isTrue ? '[开启]' : '[关闭]';
            }
            
            return `${icon} ${item.label} ${status}`;
        });
        
        menuOpts.push('🔙 返回上级');
        
        const choice = ui.menu('选择配置项进行修改', menuOpts);
        if (!choice || choice.includes('返回')) break;
        
        const idx = menuOpts.indexOf(choice);
        const item = items[idx];
        
        console.log(`\n设置项: ${item.key}`);
        console.log(`说明: ${item.desc}\n`);
        
        let curVal;
        if (item.file === 'json') curVal = getNestedValue(jsonConfig, item.key);
        else curVal = envConfig[item.key];
        
        if (item.type === 'bool') {
            const nextVal = !(curVal === true || curVal === 'true');
            if (item.file === 'json') {
                setNestedValue(jsonConfig, item.key, nextVal);
                saveJson(jsonConfig);
            } else {
                envConfig[item.key] = nextVal;
                saveEnv(envConfig);
            }
            const colorText = nextVal ? `${env.colors.green}开启${env.colors.nc}` : `${env.colors.red}关闭${env.colors.nc}`;
            ui.print('success', `已切换为: ${colorText}`);
        } else if (item.type === 'select') {
            const optChoice = ui.menu(`选择 ${item.label}`, item.options);
            if (optChoice) {
                if (item.file === 'json') {
                    setNestedValue(jsonConfig, item.key, optChoice);
                    saveJson(jsonConfig);
                } else {
                    envConfig[item.key] = optChoice;
                    saveEnv(envConfig);
                }
                ui.print('success', `已保存: ${optChoice}`);
            }
        } else {
            const input = ui.input(`请输入新值`, String(curVal || ''));
            if (input !== null) {
                let finalVal = input;
                if (item.type === 'int') {
                    finalVal = parseInt(input);
                    if (isNaN(finalVal)) {
                        ui.print('error', '无效的整数');
                        ui.pause();
                        continue;
                    }
                } else if (item.type === 'float') {
                    finalVal = parseFloat(input);
                    if (isNaN(finalVal)) {
                        ui.print('error', '无效的数字');
                        ui.pause();
                        continue;
                    }
                }
                
                if (item.file === 'json') {
                    setNestedValue(jsonConfig, item.key, finalVal);
                    saveJson(jsonConfig);
                } else {
                    envConfig[item.key] = finalVal;
                    saveEnv(envConfig);
                }
                ui.print('success', '已保存');
            }
        }
        ui.pause();
    }
}

function mainMenu() {
    if (!fs.existsSync(AG_DIR)) {
        ui.print('error', '未安装 Antigravity 模块。');
        return;
    }

    while (true) {
        ui.header('Antigravity 配置管理');
        
        const opts = [
            '🌐 服务配置',
            '🔐 安全凭据',
            '🔄 代理设置',
            '⚙️  模型参数',
            '🔂 轮询策略',
            '🛠️  高级设置',
            '🔙 返回'
        ];
        
        const choice = ui.menu('请选择配置类别', opts);
        if (!choice || choice.includes('返回')) break;
        
        if (choice.includes('服务')) renderCategory('服务配置', schemas.server);
        else if (choice.includes('安全')) renderCategory('安全凭据', schemas.security);
        else if (choice.includes('代理')) renderCategory('代理设置', schemas.proxy);
        else if (choice.includes('模型')) renderCategory('模型默认参数', schemas.defaults);
        else if (choice.includes('轮询')) renderCategory('轮询策略', schemas.rotation);
        else if (choice.includes('高级')) renderCategory('高级设置', schemas.advanced);
    }
}

mainMenu();
