export default {
  async fetch(request, env, ctx) {
    const userAgent = request.headers.get('User-Agent') || '';
    
    // 1. 如果不是 curl/wget，返回 HTML 指引页面
    if (!userAgent.includes('curl') && !userAgent.includes('wget')) {
      const html = `<!DOCTYPE html>
      <html lang="en">
      <head><title>TAV-X Installer</title><style>body{background:#1e1e1e;color:#ccc;display:flex;justify-content:center;align-items:center;height:100vh;font-family:monospace}code{background:#333;padding:10px;border-radius:5px}</style></head>
      <body><code>curl -s -L https://tav-x.future404.qzz.io | bash</code></body>
      </html>`;
      return new Response(html, { headers: { 'content-type': 'text/html;charset=UTF-8' } });
    }
    
    // 2. 如果是安装请求，去 GitHub 拉取最新脚本
    // 使用时间戳防止 CF 缓存
    const scriptUrl = "https://raw.githubusercontent.com/Future-404/TAV-X/main/st.sh?t=" + Date.now();
    
    try {
      const ghRes = await fetch(scriptUrl, {
        headers: { 
          'User-Agent': 'TAV-X-Worker', 
          'Cache-Control': 'no-cache', 
          'Pragma': 'no-cache' 
        }
      });
      
      if (!ghRes.ok) throw new Error("GitHub Error");
      
      // 3. 核心逻辑：注入安装模式标记
      const originalScript = await ghRes.text();
      const injectedScript = "export TAVX_INSTALLER_MODE=true\n" + originalScript;
      
      return new Response(injectedScript, { 
        headers: { 'content-type': 'text/plain;charset=UTF-8' } 
      });
      
    } catch (e) {
      // 4. 错误回落
      return new Response(`#!/bin/bash\necho "Error: Fetch failed - ${e.message}"`, { status: 502 });
    }
  }
};