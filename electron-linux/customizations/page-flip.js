/* 白虎阅读 — 章节切换 3D 翻书动画 JS Hook
 *
 * 触发条件：阅读页(#/read/)内章节标题(.read-region p.title)发生变化
 *   章节切换走 jumpToChapter() 内部状态，URL 不变，
 *   因此用 MutationObserver 观察正文 DOM，而非 pushState
 * 动画方案：缓存的旧章节克隆翻出 → 新内容翻入
 */

(function () {
    'use strict';

    let inFlight = false;
    let lastTitle = '';
    let cachedGhost = null;
    let cacheTimer = null;

    function onReadPage() {
        return location.hash.startsWith('#/read/');
    }

    function currentTitle() {
        const el = document.querySelector('.read-region p.title');
        return el ? el.textContent.trim() : '';
    }

    function findStage() {
        return document.querySelector('.read-screen') || document.querySelector('app-root');
    }

    // DOM 稳定后缓存当前章节内容，作为下次翻页时"旧页"的克隆
    function scheduleCache() {
        clearTimeout(cacheTimer);
        cacheTimer = setTimeout(() => {
            if (!onReadPage() || inFlight) return;
            const stage = findStage();
            if (stage) cachedGhost = stage.cloneNode(true);
        }, 400);
    }

    function triggerFlip() {
        if (inFlight || !onReadPage()) return;
        const stage = findStage();
        if (!stage || !stage.parentElement) return;

        inFlight = true;
        document.documentElement.classList.add('page-flipping');

        let wrapper = null;
        if (cachedGhost) {
            cachedGhost.classList.add('page-flip-out');
            wrapper = document.createElement('div');
            wrapper.style.cssText = 'position:absolute;inset:0;pointer-events:none;z-index:5;overflow:hidden;';
            wrapper.appendChild(cachedGhost);
            const parent = stage.parentElement;
            if (getComputedStyle(parent).position === 'static') {
                parent.style.position = 'relative';
            }
            parent.appendChild(wrapper);
        }

        // 新内容（已在 DOM 中）翻入
        stage.classList.add('page-flip-in');

        setTimeout(() => {
            stage.classList.remove('page-flip-in');
            if (wrapper) wrapper.remove();
            document.documentElement.classList.remove('page-flipping');
            inFlight = false;
            cachedGhost = null;
            scheduleCache();
        }, 780);
    }

    const observer = new MutationObserver(() => {
        if (inFlight) return;
        if (!onReadPage()) {
            lastTitle = '';
            cachedGhost = null;
            return;
        }
        const title = currentTitle();
        // 章节交换的瞬态（旧内容已移除、新内容未插入）不清空 lastTitle
        if (!title) return;
        if (lastTitle && title !== lastTitle) {
            lastTitle = title;
            // 给 Angular 一点时间完成新章节渲染
            setTimeout(triggerFlip, 60);
            return;
        }
        lastTitle = title;
        scheduleCache();
    });

    observer.observe(document.body, {childList: true, subtree: true});

    // 调试入口：控制台执行 window.__pomFlip() 手动触发一次（需在阅读页）
    window.__pomFlip = triggerFlip;
})();
