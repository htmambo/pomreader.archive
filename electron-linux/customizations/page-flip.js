/* 白虎阅读 — 章节切换 3D 翻书动画 JS Hook
 * 监听 Angular 路由 pushState 触发章节切换
 * 仅对 app-root 顶层做翻书动画，不干扰 ng-zorro 内部组件
 *
 * 触发条件：URL 路径发生变化（Angular Router pushState）
 * 动画方案：克隆当前内容 → 翻出 → 翻入新内容
 */

(function () {
    'use strict';

    let lastUrl = location.href;
    let inFlight = false;

    function findRoot() {
        return document.querySelector('app-root') || document.body.firstElementChild;
    }

    function triggerFlip() {
        if (inFlight) return;
        const root = findRoot();
        if (!root || !root.parentElement) return;

        inFlight = true;
        document.documentElement.classList.add('page-flipping');

        // 克隆当前可见内容（旧章节）
        const ghost = root.cloneNode(true);
        ghost.classList.add('page-flip-out');

        // 用一个临时 wrapper 让 absolute 定位生效
        const wrapper = document.createElement('div');
        wrapper.style.cssText = 'position:absolute;inset:0;pointer-events:none;z-index:5;';
        wrapper.appendChild(ghost);

        const parent = root.parentElement;
        if (getComputedStyle(parent).position === 'static') {
            parent.style.position = 'relative';
        }
        parent.appendChild(wrapper);

        // 新内容（仍在原位）翻入
        root.classList.add('page-flip-in');

        setTimeout(() => {
            root.classList.remove('page-flip-in');
            wrapper.remove();
            document.documentElement.classList.remove('page-flipping');
            inFlight = false;
        }, 780);
    }

    // Hook pushState / replaceState（Angular Router 走这个）
    ['pushState', 'replaceState'].forEach((fn) => {
        const orig = history[fn];
        history[fn] = function () {
            const result = orig.apply(this, arguments);
            // 微任务内检测 URL 是否真的变化（避免重复触发）
            queueMicrotask(() => {
                if (location.href !== lastUrl) {
                    lastUrl = location.href;
                    // 给 Angular 一点时间渲染新内容
                    setTimeout(triggerFlip, 60);
                }
            });
            return result;
        };
    });

    // 兜底：popstate（前进/后退）
    window.addEventListener('popstate', () => {
        if (location.href !== lastUrl) {
            lastUrl = location.href;
            setTimeout(triggerFlip, 60);
        }
    });

    // 调试入口
    window.__pomFlip = triggerFlip;
})();