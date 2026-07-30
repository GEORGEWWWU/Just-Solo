#include "MarkdownHelper.h"

#include <cmark-gfm.h>
#include <cmark-gfm-extension_api.h>
#include <cmark-gfm-core-extensions.h>

static QString wrapStyling(const QString &bodyHtml)
{
    // 内联样式，适配 QML RichText 引擎 + CHANGELOG.md 的配色风格
    return QStringLiteral(
        "<html><head><style>"
        "body{color:#ffffff;font-size:13px;}"
        "a{color:#3B82F6;}"
        "h1{font-size:20px;font-weight:bold;margin:12px 0 8px 0;}"
        "h2{font-size:17px;font-weight:bold;margin:10px 0 6px 0;color:#cccccc;}"
        "h3{font-size:15px;font-weight:bold;margin:8px 0 4px 0;}"
        "ul{margin:4px 0;padding-left:20px;}"
        "ol{margin:4px 0;padding-left:20px;}"
        "li{margin:2px 0;}"
        "p{margin:4px 0;}"
        "blockquote{margin:4px 0;padding:4px 12px;border-left:3px solid #555;color:#aaaaaa;}"
        "code{background-color:#2a2a2a;padding:1px 4px;border-radius:3px;font-size:12px;}"
        "pre{background-color:#2a2a2a;padding:8px;border-radius:4px;margin:4px 0;}"
        "</style></head><body>%1</body></html>"
    ).arg(bodyHtml);
}

QString MarkdownHelper::toHtml(const QString &markdown)
{
    if (markdown.isEmpty())
        return {};

    // 注册 GFM 扩展（table、strikethrough、autolink、tagfilter）
    cmark_gfm_core_extensions_ensure_registered();

    QByteArray utf8 = markdown.toUtf8();

    // 创建解析器并挂载 GFM 扩展
    cmark_parser *parser = cmark_parser_new(CMARK_OPT_DEFAULT);
    if (!parser)
        return {};

    static const char *extNames[] = {"table", "autolink", "tagfilter", "strikethrough"};
    for (auto name : extNames) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension(name);
        if (ext)
            cmark_parser_attach_syntax_extension(parser, ext);
    }

    cmark_parser_feed(parser, utf8.constData(), utf8.size());
    cmark_node *doc = cmark_parser_finish(parser);
    cmark_parser_free(parser);

    if (!doc)
        return {};

    // 构造扩展列表，用于渲染阶段
    cmark_llist *exts = nullptr;
    for (auto name : extNames) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension(name);
        if (ext)
            exts = cmark_llist_append(cmark_get_default_mem_allocator(), exts, ext);
    }

    char *rawHtml = cmark_render_html(doc, CMARK_OPT_DEFAULT, exts);
    cmark_llist_free(cmark_get_default_mem_allocator(), exts);
    cmark_node_free(doc);

    if (!rawHtml)
        return {};

    QString html = QString::fromUtf8(rawHtml);
    free(rawHtml);

    return wrapStyling(html);
}
