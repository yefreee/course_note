'use strict';

module.exports = ctx => function (args, content) {
    return `<div class="nocopy">${ctx.render.renderSync({ text: content, engine: 'markdown' })}</div>`;
};
