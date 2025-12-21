hexo.extend.tag.register('nocopy', function (args, content) {
    return '<div class="nocopy">\n\n' + content + '\n\n</div>';
}, { ends: true });
