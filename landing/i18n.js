const STORAGE_KEY = "quiet-landing-language";
const SUPPORTED_LANGUAGES = ["en", "zh"];
const CHINESE_REGION_CODES = new Set(["CN", "HK", "MO", "TW"]);

const translations = {
  en: {
    meta: {
      title: "Quiet — A calm file organizer for Mac",
      description: "Quiet is a lightweight Mac app that sits in your menu bar and organizes files on your own computer. No cloud, no accounts, no clutter."
    },
    nav: {
      aria: "Primary",
      workflow: "How it works",
      privacy: "Privacy",
      download: "Download",
      cta: "Get Quiet"
    },
    language: {
      label: "EN",
      aria: "Switch language to Chinese"
    },
    demo: {
      aria: "Quiet demo video"
    },
    hero: {
      releaseAria: "Product update",
      releaseBadge: "New",
      releaseText: "Now in the macOS menu bar",
      copy: "Quiet is a tiny menu-bar app that tidies your files so you don't have to. Drag anything onto it — it figures out what you dropped, renames the mess, and puts everything where it belongs. All on your Mac.",
      primaryCta: "Download for Mac",
      secondaryCta: "See how it works"
    },
    workflow: {
      eyebrow: "Your Mac. Your files. No cloud involved.",
      title: "Drag in clutter. Get back calm."
    },
    features: {
      drag: {
        title: "Drag in. Stop thinking.",
        copy: "Drop files, folders, or screenshots onto Quiet's menu-bar icon. It handles the rest — you go back to whatever you were doing."
      },
      native: {
        title: "Feels built into your Mac",
        copy: "Quiet lives in the menu bar and opens like a system popover. No Electron, no sluggish web wrapper — just a native app that starts up instantly and stays out of your way."
      },
      local: {
        title: "Your files never leave your Mac",
        copy: "Everything happens on your own computer. No sign-up, no cloud storage, no one else's server reading your documents. Your organizing rules are yours to customize and keep."
      }
    },
    download: {
      eyebrow: "Quiet Desktop",
      title: "Give your files a calm place to land.",
      cta: "Download Quiet"
    }
  },
  zh: {
    meta: {
      title: "Quiet — 让 Mac 桌面安静下来的文件整理工具",
      description: "Quiet 是一个轻量的 Mac 菜单栏应用，在本地帮你整理文件。无需注册，无需云存储，干净利落。"
    },
    nav: {
      aria: "主导航",
      workflow: "怎么用",
      privacy: "隐私",
      download: "下载",
      cta: "获取 Quiet"
    },
    language: {
      label: "中",
      aria: "切换语言为英文"
    },
    demo: {
      aria: "Quiet 演示视频"
    },
    hero: {
      releaseAria: "产品更新",
      releaseBadge: "New",
      releaseText: "现已支持 macOS 菜单栏",
      copy: "Quiet 是一个轻巧的菜单栏应用，帮你把杂乱的文件夹收拾得井井有条。文件拖进去就行——它会自动识别内容、理顺命名、归档到合适的位置。全程在你自己的 Mac 上完成。",
      primaryCta: "下载 Mac 版",
      secondaryCta: "看看怎么用"
    },
    workflow: {
      eyebrow: "你的 Mac，你的文件，不依赖任何云端服务。",
      title: "拖进去的是杂乱，还给你的是清净。"
    },
    features: {
      drag: {
        title: "拖进去，就不用管了",
        copy: "把文件、文件夹或截图直接拖到 Quiet 的菜单栏图标上。剩下的交给它，你继续做自己的事。"
      },
      native: {
        title: "像 Mac 自带的功能一样",
        copy: "Quiet 常驻菜单栏，点开就像系统自带弹窗一样轻快。不需要 Electron，也不吃资源——真正的原生应用，秒开秒关。"
      },
      local: {
        title: "你的文件，不出你的电脑",
        copy: "所有处理都在本地完成。不需要注册账号，没有云端存储，没有第三方服务器读你的文档。整理规则完全由你自己定义和掌控。"
      }
    },
    download: {
      eyebrow: "Quiet Desktop",
      title: "给你的文件一个安静落点。",
      cta: "下载 Quiet"
    }
  }
};

function getNestedValue(source, path) {
  return path.split(".").reduce((value, key) => (value ? value[key] : undefined), source);
}

function normalizeLanguage(language) {
  return SUPPORTED_LANGUAGES.includes(language) ? language : "en";
}

function languageFromUrl() {
  const language = new URLSearchParams(window.location.search).get("lang");
  return SUPPORTED_LANGUAGES.includes(language) ? language : null;
}

function browserLanguageFallback() {
  const language = navigator.languages?.[0] || navigator.language || "";
  return language.toLowerCase().startsWith("zh") ? "zh" : "en";
}

async function detectLanguageByIp() {
  const controller = new AbortController();
  const timeoutId = window.setTimeout(() => controller.abort(), 1600);

  try {
    const response = await fetch("https://ipapi.co/json/", {
      cache: "no-store",
      signal: controller.signal
    });

    if (!response.ok) {
      throw new Error("Geo lookup failed");
    }

    const data = await response.json();
    return CHINESE_REGION_CODES.has(String(data.country_code || "").toUpperCase()) ? "zh" : "en";
  } finally {
    window.clearTimeout(timeoutId);
  }
}

function applyLanguage(language) {
  const activeLanguage = normalizeLanguage(language);
  const dictionary = translations[activeLanguage];

  document.documentElement.lang = activeLanguage === "zh" ? "zh-CN" : "en";
  document.title = dictionary.meta.title;

  const metaDescription = document.querySelector('meta[name="description"]');
  if (metaDescription) {
    metaDescription.setAttribute("content", dictionary.meta.description);
  }

  document.querySelectorAll("[data-i18n]").forEach(element => {
    const value = getNestedValue(dictionary, element.dataset.i18n);
    if (typeof value === "string") {
      element.textContent = value;
    }
  });

  document.querySelectorAll("[data-i18n-attr]").forEach(element => {
    element.dataset.i18nAttr.split(",").forEach(binding => {
      const [attribute, path] = binding.split(":").map(part => part.trim());
      const value = getNestedValue(dictionary, path);
      if (attribute && typeof value === "string") {
        element.setAttribute(attribute, value);
      }
    });
  });

  const toggle = document.querySelector("[data-language-toggle]");
  const label = document.querySelector("[data-language-label]");

  if (toggle && label) {
    label.textContent = dictionary.language.label;
    toggle.setAttribute("aria-label", dictionary.language.aria);
    toggle.dataset.currentLanguage = activeLanguage;
  }
}

async function resolveInitialLanguage() {
  const urlLanguage = languageFromUrl();
  if (urlLanguage) {
    localStorage.setItem(STORAGE_KEY, urlLanguage);
    return urlLanguage;
  }

  const savedLanguage = localStorage.getItem(STORAGE_KEY);
  if (SUPPORTED_LANGUAGES.includes(savedLanguage)) {
    return savedLanguage;
  }

  try {
    return await detectLanguageByIp();
  } catch {
    return browserLanguageFallback();
  }
}

function bindLanguageToggle() {
  const toggle = document.querySelector("[data-language-toggle]");
  if (!toggle) {
    return;
  }

  toggle.addEventListener("click", () => {
    const nextLanguage = toggle.dataset.currentLanguage === "zh" ? "en" : "zh";
    localStorage.setItem(STORAGE_KEY, nextLanguage);
    applyLanguage(nextLanguage);
  });
}

applyLanguage("en");
bindLanguageToggle();
resolveInitialLanguage().then(applyLanguage);
