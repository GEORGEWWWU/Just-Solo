#pragma once

#include <QString>

class MarkdownHelper
{
public:
    /// 将 Markdown 文本转换为带样式的 HTML，适配 QML RichText 渲染
    static QString toHtml(const QString &markdown);
};
