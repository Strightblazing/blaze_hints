(() => {
    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'blaze_hints';

    const post = (name, data = {}) =>
        fetch(`https://${resource}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        }).then((r) => r.json()).catch(() => null);

    const $ = (id) => document.getElementById(id);
    const el = (tag, cls, text) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;
        return e;
    };
    let current = null; // open screen name

    function show(name) {
        document.querySelectorAll('.screen').forEach((s) => s.classList.add('hidden'));
        current = name;
        if (name) $(name).classList.remove('hidden');
    }

    function close(notify = true) {
        dlgFinishTyping();
        show(null);
        if (notify) post('close');
    }

    // small click for keypad / tile buttons (no notification sounds anywhere)
    let audio;
    function click() {
        try {
            audio = audio || new (window.AudioContext || window.webkitAudioContext)();
            const o = audio.createOscillator();
            const g = audio.createGain();
            o.type = 'square';
            o.frequency.value = 1300;
            g.gain.setValueAtTime(0.04, audio.currentTime);
            g.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + 0.05);
            o.connect(g).connect(audio.destination);
            o.start();
            o.stop(audio.currentTime + 0.06);
        } catch (e) { /* audio is optional */ }
    }

    const triesText = (n) => (n === 1 ? '1 try left' : `${n} tries left`);

    function renderTiles(box, tiles, onPick) {
        box.innerHTML = '';
        box.classList.toggle('hidden', !tiles || !tiles.length);
        (tiles || []).forEach((t) => {
            const s = el('span', '', t);
            if (onPick) s.addEventListener('click', () => onPick(s, t));
            box.appendChild(s);
        });
    }

    // ---------------- Keypad ----------------
    const kp = { length: 4, value: '', busy: false };
    const panel = $('kp-panel');

    function kpRender() {
        const dots = $('kp-dots');
        dots.innerHTML = '';
        for (let i = 0; i < kp.length; i++) {
            const s = el('span');
            if (i < kp.value.length) s.className = 'on';
            dots.appendChild(s);
        }
    }

    function kpOpen(data) {
        kp.length = Math.max(1, Math.min(12, data.length || 4));
        kp.value = '';
        kp.busy = false;
        panel.className = 'kp-panel';
        $('kp-title').textContent = data.title || 'Enter code';
        $('kp-tries').textContent = triesText(data.triesLeft ?? 3);
        renderTiles($('kp-tiles'), data.tiles);
        kpRender();
        show('keypad');
    }

    async function kpSubmit() {
        if (kp.busy || kp.value.length === 0) return;
        kp.busy = true;
        panel.classList.add('busy');
        const res = (await post('keypadSubmit', { code: kp.value })) || { ok: false, closed: true };
        if (current !== 'keypad') return;

        if (res.ok) {
            panel.className = 'kp-panel correct busy';
            setTimeout(() => current === 'keypad' && close(), 1000);
            return;
        }
        if (res.closed) return close();

        panel.className = 'kp-panel';
        void panel.offsetWidth; // restart the shake animation
        panel.className = 'kp-panel wrong busy';
        $('kp-tries').textContent = triesText(res.triesLeft ?? 0);

        if (res.locked) {
            setTimeout(() => current === 'keypad' && close(), 1200);
            return;
        }
        setTimeout(() => {
            kp.value = '';
            kp.busy = false;
            panel.className = 'kp-panel';
            kpRender();
        }, 650);
    }

    function kpKey(k) {
        if (kp.busy) return;
        click();
        if (k === 'clr') kp.value = '';
        else if (k === 'ok') return kpSubmit();
        else if (/^[0-9]$/.test(k) && kp.value.length < kp.length) kp.value += k;
        kpRender();
    }

    $('kp-grid').addEventListener('click', (e) => {
        const b = e.target.closest('button');
        if (b) kpKey(b.dataset.k);
    });

    function flash(k) {
        const b = document.querySelector(`#kp-grid button[data-k="${k}"]`);
        if (!b) return;
        b.classList.add('press');
        setTimeout(() => b.classList.remove('press'), 90);
    }

    // ---------------- Word entry ----------------
    const wd = { length: 6, busy: false };
    const wdPanel = $('wd-panel');
    const wdInput = $('wd-input');

    function wdOpen(data) {
        wd.length = Math.max(1, Math.min(12, data.length || 6));
        wd.busy = false;
        wdPanel.className = 'kp-panel wd-panel';
        $('wd-title').textContent = data.title || 'Enter the word';
        $('wd-tries').textContent = triesText(data.triesLeft ?? 3);
        wdInput.value = '';
        wdInput.maxLength = wd.length;
        wdInput.placeholder = '_'.repeat(wd.length);
        renderTiles($('wd-tiles'), data.tiles, (span, letter) => {
            if (wd.busy || span.classList.contains('used') || wdInput.value.length >= wd.length) return;
            click();
            span.classList.add('used');
            wdInput.value += letter;
            wdInput.focus();
        });
        show('word');
        setTimeout(() => wdInput.focus(), 50);
    }

    function wdResetTiles() {
        document.querySelectorAll('#wd-tiles span').forEach((s) => s.classList.remove('used'));
    }

    async function wdSubmit() {
        if (wd.busy || !wdInput.value.trim()) return;
        wd.busy = true;
        const res = (await post('keypadSubmit', { code: wdInput.value.trim() })) || { ok: false, closed: true };
        if (current !== 'word') return;
        if (res.ok) {
            wdPanel.className = 'kp-panel wd-panel correct';
            setTimeout(() => current === 'word' && close(), 1000);
            return;
        }
        if (res.closed) return close();
        wdPanel.className = 'kp-panel wd-panel';
        void wdPanel.offsetWidth;
        wdPanel.className = 'kp-panel wd-panel wrong';
        $('wd-tries').textContent = triesText(res.triesLeft ?? 0);
        if (res.locked) {
            setTimeout(() => current === 'word' && close(), 1200);
            return;
        }
        setTimeout(() => {
            wd.busy = false;
            wdPanel.className = 'kp-panel wd-panel';
            wdInput.value = '';
            wdResetTiles();
            wdInput.focus();
        }, 650);
    }

    wdInput.addEventListener('input', () => {
        wdInput.value = wdInput.value.toUpperCase().replace(/[^A-Z0-9]/g, '');
        if (!wdInput.value) wdResetTiles();
    });
    $('wd-submit').addEventListener('click', wdSubmit);
    $('wd-cancel').addEventListener('click', () => close());

    // ---------------- Dialog ----------------
    const dlg = { typing: null, full: '', replies: [], busy: false };

    function initials(name) {
        return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join('');
    }

    function dlgOpen(data) {
        $('dialog').className = `screen dialog ${data.style === 'classic' ? 'classic' : 'cinematic'}`;
        $('dlg-name').textContent = data.name || '';
        $('dlg-avatar').textContent = initials(data.name);
        $('dlg-text').textContent = '';
        $('dlg-replies').innerHTML = '';
        dlg.busy = false;
        show('dialog');
    }

    function dlgFinishTyping() {
        if (!dlg.typing) return false;
        clearInterval(dlg.typing);
        dlg.typing = null;
        $('dlg-text').textContent = dlg.full;
        $('dlg-replies').classList.remove('waiting');
        return true;
    }

    function dlgLine(data) {
        if (current !== 'dialog') return;
        dlg.busy = false;
        dlg.full = data.text || '';
        dlg.replies = data.replies || [];

        const box = $('dlg-replies');
        box.innerHTML = '';
        box.classList.add('waiting');
        dlg.replies.forEach((label, i) => {
            const b = el('button');
            b.dataset.i = i + 1;
            b.appendChild(el('span', 'num', String(i + 1)));
            b.appendChild(el('span', '', label));
            box.appendChild(b);
        });

        // typewriter (click or any reply key skips it)
        dlgFinishTyping();
        const t = $('dlg-text');
        t.textContent = '';
        let n = 0;
        dlg.typing = setInterval(() => {
            n += 2;
            t.textContent = dlg.full.slice(0, n);
            if (n >= dlg.full.length) dlgFinishTyping();
        }, 22);
    }

    function dlgReply(i) {
        if (current !== 'dialog' || dlg.busy) return;
        if (dlgFinishTyping()) return;
        if (i < 1 || i > dlg.replies.length) return;
        const b = document.querySelector(`#dlg-replies button[data-i="${i}"]`);
        if (b) { b.classList.add('press'); setTimeout(() => b.classList.remove('press'), 120); }
        dlg.busy = true;
        post('dialogReply', { index: i });
    }

    $('dlg-replies').addEventListener('click', (e) => {
        const b = e.target.closest('button');
        if (b) dlgReply(Number(b.dataset.i));
    });
    $('dlg-text').addEventListener('click', dlgFinishTyping);

    // ---------------- Note reader ----------------
    function noteOpen(data) {
        $('note-card').className = `note-card${data.kind === 'receipt' ? ' receipt' : ''}`;
        $('note-title').textContent = data.title || '';
        $('note-text').textContent = data.text || '';
        show('note');
    }
    $('note-close').addEventListener('click', () => close());

    // ---------------- Inspect overlay ----------------
    function inspectOpen(data) {
        $('ins-caption').textContent = data.caption || '';
        $('ins-circle').classList.toggle('hidden', !data.circle);
        const piece = $('ins-piece');
        piece.textContent = data.pieceText || '';
        piece.classList.toggle('hidden', !data.pieceText);
        $('ins-stop').textContent = data.stopText || '[E] Stop inspecting';
        show('inspect');
    }

    // ---------------- Builder ----------------
    const B = { hints: [], hint: null, sel: -1, dirty: false, presets: [], defaults: {}, cinematicDefault: true };
    const TYPE_LABEL = { message: 'Message', inspect: 'Inspect spot', npc: 'NPC', password: 'Password', scene: 'World scene', stash: 'Personal stash' };
    const clone = (o) => JSON.parse(JSON.stringify(o));
    const uid = () => 'b' + Date.now().toString(36) + Math.floor(Math.random() * 1000).toString(36);
    const isObj = (v) => v && typeof v === 'object' && !Array.isArray(v);

    // Lua sends empty tables as [] : turn the ones that are objects back into objects
    function normalizeStep(s) {
        ['sources', 'timeLock', 'scene', 'coords'].forEach((k) => {
            if (Array.isArray(s[k])) s[k] = s[k].length ? s[k] : undefined;
        });
        if (s.scene && Array.isArray(s.scene.effects)) s.scene.effects = {};
        if (s.scene && Array.isArray(s.scene.coords)) delete s.scene.coords;
        if (Array.isArray(s.dialog)) s.dialog.forEach((l) => { if (!Array.isArray(l.replies)) l.replies = []; });
        if (s.timeLock && !Array.isArray(s.timeLock.days)) s.timeLock.days = [];
        return s;
    }

    function loadHint(h) {
        B.hint = h ? clone(h) : { id: null, name: 'New hint', enabled: true, autoStart: true, steps: [] };
        B.hint.steps = (Array.isArray(B.hint.steps) ? B.hint.steps : []).map(normalizeStep);
        B.sel = B.hint.steps.length ? 0 : -1;
        setDirty(false);
        renderBuilder();
    }

    function setDirty(v) {
        B.dirty = v;
        $('bd-save').classList.toggle('bd-save-dirty', v);
    }
    const touch = () => setDirty(true);

    function stepSummary(s) {
        switch (s.type) {
            case 'message': return `${s.trigger || 'after_previous'}${s.piece ? ' · piece' : ''}${s.deliver === 'note' ? ' · note' : ''}`;
            case 'inspect': return `${s.label || 'Inspect'}${s.piece ? ' · piece' : ''}`;
            case 'npc': return `${s.name || 'Stranger'}${s.coords ? '' : ' · not placed'}`;
            case 'password': return `${s.inputType || 'keypad'} · ${s.codeMode || 'random'}`;
            case 'scene': return s.scene ? s.scene.preset : 'no preset';
            case 'stash': return `${s.mode || 'permanent'} · ${(s.rewards || []).length} rewards`;
        }
        return '';
    }

    function renderSide() {
        const sel = $('bd-hint');
        sel.innerHTML = '';
        B.hints.forEach((h) => {
            const o = el('option', '', `#${h.id} ${h.name}`);
            o.value = h.id;
            sel.appendChild(o);
        });
        const n = el('option', '', '+ New hint');
        n.value = 'new';
        sel.appendChild(n);
        sel.value = B.hint.id ? String(B.hint.id) : 'new';

        $('bd-name').value = B.hint.name || '';
        $('bd-enabled').checked = B.hint.enabled !== false;
        $('bd-auto').checked = B.hint.autoStart !== false;
        $('bd-reset').disabled = !B.hint.id;
        $('bd-delete').disabled = !B.hint.id;

        const list = $('bd-steps');
        list.innerHTML = '';
        if (!B.hint.steps.length) list.appendChild(el('div', 'bd-empty', 'No steps yet. Add one below.'));
        B.hint.steps.forEach((s, i) => {
            const row = el('div', `bd-step${i === B.sel ? ' sel' : ''}`);
            row.appendChild(el('div', 'n', String(i + 1)));
            const t = el('div', 't');
            t.appendChild(el('b', '', TYPE_LABEL[s.type] || s.type));
            t.appendChild(el('small', '', stepSummary(s)));
            row.appendChild(t);
            const mv = el('div', 'mv');
            const up = el('button', '', '▲');
            const down = el('button', '', '▼');
            const del = el('button', '', '✕');
            up.onclick = (e) => { e.stopPropagation(); moveStep(i, -1); };
            down.onclick = (e) => { e.stopPropagation(); moveStep(i, 1); };
            del.onclick = (e) => { e.stopPropagation(); deleteStep(i); };
            mv.append(up, down, del);
            row.appendChild(mv);
            row.onclick = () => { B.sel = i; renderBuilder(); };
            list.appendChild(row);
        });
    }

    function moveStep(i, d) {
        const j = i + d;
        const steps = B.hint.steps;
        if (j < 0 || j >= steps.length) return;
        [steps[i], steps[j]] = [steps[j], steps[i]];
        if (B.sel === i) B.sel = j; else if (B.sel === j) B.sel = i;
        touch();
        renderBuilder();
    }

    let deleteArmed = null;
    function deleteStep(i) {
        // two clicks within 3 s (no blocking confirm popups in NUI)
        if (deleteArmed !== i) {
            deleteArmed = i;
            setTimeout(() => { if (deleteArmed === i) deleteArmed = null; }, 3000);
            const row = $('bd-steps').children[i];
            if (row) row.querySelector('.t small').textContent = 'Click ✕ again to delete';
            return;
        }
        deleteArmed = null;
        B.hint.steps.splice(i, 1);
        if (B.sel >= B.hint.steps.length) B.sel = B.hint.steps.length - 1;
        touch();
        renderBuilder();
    }

    // ---- field helpers ----
    function fld(label, input, hint) {
        const f = el('label', 'fld');
        f.appendChild(el('span', '', label));
        f.appendChild(input);
        if (hint) f.appendChild(el('em', '', hint));
        return f;
    }

    // type: text | textarea | number | select | check
    function input(obj, key, type, opts = {}) {
        let i;
        const val = obj[key];
        if (type === 'textarea') {
            i = el('textarea', 'inp');
            i.value = val ?? '';
            i.oninput = () => { obj[key] = i.value; touch(); };
        } else if (type === 'select') {
            i = el('select', 'inp');
            opts.options.forEach(([v, l]) => {
                const o = el('option', '', l);
                o.value = v;
                i.appendChild(o);
            });
            const shown = opts.show ? opts.show(val) : val;
            i.value = shown ?? opts.def ?? opts.options[0][0];
            if (val === undefined && opts.def !== undefined && !opts.show) obj[key] = opts.def;
            i.onchange = () => {
                obj[key] = opts.parse ? opts.parse(i.value) : i.value;
                touch();
                if (opts.rerender !== false) renderCards();
                renderSide();
            };
        } else if (type === 'check') {
            const l = el('label', 'chk');
            const c = el('input');
            c.type = 'checkbox';
            c.checked = val === undefined ? opts.def === true : val === true;
            c.onchange = () => { obj[key] = c.checked; touch(); renderSide(); };
            l.append(c, el('span', '', opts.label || ''));
            return l;
        } else {
            i = el('input', 'inp');
            i.type = type === 'number' ? 'number' : 'text';
            if (opts.min !== undefined) i.min = opts.min;
            if (opts.max !== undefined) i.max = opts.max;
            if (opts.placeholder) i.placeholder = opts.placeholder;
            const shown = opts.show ? opts.show(val) : val;
            i.value = shown ?? '';
            if (opts.def !== undefined && (val === undefined || val === '')) i.placeholder = String(opts.def);
            i.oninput = () => {
                let v = i.value;
                if (opts.parse) v = opts.parse(v);
                else if (type === 'number') v = v === '' ? undefined : Number(v);
                else if (v === '') v = undefined;
                obj[key] = v;
                touch();
            };
        }
        return i;
    }

    function card(title, wide, extra) {
        const c = el('div', `card${wide ? ' wide' : ''}`);
        const h = el('h2', '', title);
        if (extra) h.appendChild(extra);
        c.appendChild(h);
        return c;
    }

    function row(...children) {
        const r = el('div', children.length === 3 ? 'row3' : 'row');
        children.forEach((c) => r.appendChild(c));
        return r;
    }

    function coordsLine(obj, key, label) {
        const c = obj[key];
        const line = el('div', `coords${c ? '' : ' unset'}`);
        line.appendChild(el('span', '', c ? `${label}: ${(+c.x).toFixed(1)}, ${(+c.y).toFixed(1)}, ${(+c.z).toFixed(1)} · ${(+(c.w || 0)).toFixed(0)}°` : `${label}: not placed`));
        if (c) {
            const clr = el('button', 'btn small ghost', 'Clear');
            clr.onclick = () => { delete obj[key]; touch(); renderCards(); renderSide(); };
            line.appendChild(clr);
        }
        return line;
    }

    const opt = (pairs) => pairs;
    const SOURCES = [['message', 'Message pieces'], ['note', 'Note item'], ['inspect', 'Inspect spot'], ['npc', 'NPC riddle'], ['receipt', 'Shop receipt'], ['scramble', 'Scramble']];

    // "Show a marker": default (config) / on / off
    function markerField(s) {
        return fld('Where-to-look marker', input(s, 'marker', 'select', {
            rerender: false,
            options: opt([['default', 'Config default'], ['on', 'Show a marker'], ['off', 'No marker']]),
            show: (v) => (v === true ? 'on' : v === false ? 'off' : 'default'),
            parse: (v) => (v === 'on' ? true : v === 'off' ? false : undefined),
        }), 'A floating ? over the spot, only for the player on this step');
    }

    // ---- cards ----
    function generalCard(s) {
        const c = card(TYPE_LABEL[s.type] || 'Step', false);
        const placeLabel = s.type === 'npc' ? 'NPC' : 'Spot';
        switch (s.type) {
            case 'message':
                c.appendChild(fld('Title', input(s, 'title', 'text', { placeholder: 'New hint' })));
                c.appendChild(fld('Text', input(s, 'text', 'textarea'), '{piece} = where the code piece goes'));
                c.appendChild(row(
                    fld('Trigger', input(s, 'trigger', 'select', { def: 'after_previous', options: opt([['after_previous', 'After previous step'], ['delay', 'After a delay'], ['zone', 'On zone enter']]) })),
                    fld('Deliver as', input(s, 'deliver', 'select', { def: 'notify', rerender: false, options: opt([['notify', 'Notification'], ['note', 'Note item']]) })),
                ));
                if (s.trigger === 'delay') c.appendChild(fld('Delay (seconds)', input(s, 'delay', 'number', { min: 0 })));
                if (s.trigger === 'zone') {
                    c.appendChild(fld('Zone radius (m)', input(s, 'radius', 'number', { min: 1, def: 5 })));
                    c.appendChild(coordsLine(s, 'coords', 'Zone'));
                }
                c.appendChild(input(s, 'piece', 'check', { label: 'Carries a code piece' }));
                break;
            case 'inspect':
                c.appendChild(fld('Target label', input(s, 'label', 'text', { placeholder: 'Inspect' })));
                c.appendChild(fld('Caption', input(s, 'text', 'textarea'), '{piece} = where the code piece goes'));
                c.appendChild(row(
                    fld('Deliver as', input(s, 'deliver', 'select', { def: 'overlay', rerender: false, options: opt([['overlay', 'Inspect overlay'], ['note', 'Note item']]) })),
                    fld('Prop model (optional)', input(s, 'prop', 'text', { placeholder: 'prop_cs_envelope_01' })),
                ));
                c.appendChild(input(s, 'piece', 'check', { label: 'Carries a code piece' }));
                c.appendChild(input(s, 'camera', 'check', { label: 'Cinematic close-up camera', def: true }));
                c.appendChild(markerField(s));
                c.appendChild(coordsLine(s, 'coords', placeLabel));
                if (!s.coords) c.appendChild(el('div', 'bd-empty', 'Not placed: uses its world scene, or the scene step right before it.'));
                break;
            case 'npc':
                c.appendChild(row(fld('Name', input(s, 'name', 'text', { placeholder: 'Stranger' })), fld('Ped model', input(s, 'model', 'text', { placeholder: 'a_m_m_business_01' }))));
                c.appendChild(row(fld('Scenario (optional)', input(s, 'scenario', 'text', { placeholder: 'WORLD_HUMAN_SMOKING' })), fld('Target label', input(s, 'label', 'text', { placeholder: 'Talk' }))));
                c.appendChild(row(
                    fld('Dialog style', input(s, 'cinematic', 'select', {
                        rerender: false,
                        options: opt([['default', `Config default (${B.cinematicDefault ? 'cinematic' : 'classic'})`], ['cinematic', 'Cinematic'], ['classic', 'Classic panel']]),
                        show: (v) => (v === true ? 'cinematic' : v === false ? 'classic' : 'default'),
                        parse: (v) => (v === 'cinematic' ? true : v === 'classic' ? false : undefined),
                    })),
                    fld('Shop id (open_shop)', input(s, 'shop', 'text')),
                ));
                c.appendChild(markerField(s));
                c.appendChild(coordsLine(s, 'coords', placeLabel));
                break;
            case 'password':
                c.appendChild(fld('Title', input(s, 'label', 'text', { placeholder: 'Enter code' })));
                c.appendChild(fld('Input', input(s, 'inputType', 'select', { def: 'keypad', options: opt([['keypad', 'Keypad (digits)'], ['word', 'Word (letter tiles)']]) })));
                c.appendChild(markerField(s));
                c.appendChild(coordsLine(s, 'coords', 'Keypad spot'));
                if (!s.coords) c.appendChild(el('div', 'bd-empty', 'Not placed: entered at the NPC right before it ("open password" reply) or on its scene.'));
                break;
            case 'scene':
                c.appendChild(fld('Arrival title', input(s, 'title', 'text', { placeholder: 'New hint' })));
                c.appendChild(fld('Arrival text (optional)', input(s, 'text', 'textarea')));
                c.appendChild(fld('Arrival radius (m)', input(s, 'radius', 'number', { min: 2, def: 15 })));
                c.appendChild(el('div', 'bd-empty', 'Set the scene below. The next step (inspect / stash / password) without a spot of its own sits on this scene.'));
                break;
            case 'stash':
                c.appendChild(row(fld('Label', input(s, 'label', 'text', { placeholder: 'Personal stash' })),
                    fld('Mode', input(s, 'mode', 'select', { def: 'permanent', rerender: false, options: opt([['permanent', 'Permanent storage'], ['reward', 'One-time reward box']]) }))));
                c.appendChild(row(fld('Slots', input(s, 'slots', 'number', { min: 1, def: B.defaults.slots })), fld('Max weight (g)', input(s, 'maxWeight', 'number', { min: 1000, def: B.defaults.maxWeight }))));
                c.appendChild(fld('Unlock message (optional)', input(s, 'unlockText', 'text')));
                c.appendChild(input(s, 'showWhileLocked', 'check', { label: 'Show it (locked) during the hint', def: true }));
                c.appendChild(markerField(s));
                c.appendChild(coordsLine(s, 'coords', 'Stash'));
                break;
        }
        return c;
    }

    function codeCard(s) {
        const c = card('Code source', false);
        s.sources = isObj(s.sources) ? s.sources : { message: true, note: true, inspect: true, npc: true, receipt: true };
        const grid = el('div', 'grid-checks');
        SOURCES.forEach(([k, l]) => grid.appendChild(input(s.sources, k, 'check', { label: l })));
        c.appendChild(grid);
        c.appendChild(el('div', 'bd-empty', 'Pieces split by themselves across the steps before this one that carry the ticked kinds. Scramble shows the letters on the code screen.'));
        c.appendChild(row(
            fld('Code', input(s, 'codeMode', 'select', { def: 'random', options: opt([['random', 'Random per player'], ['fixed', 'Fixed']]) })),
            s.codeMode === 'fixed' ? fld('Fixed code / word', input(s, 'code', 'text')) : fld('Length', input(s, 'length', 'number', { min: 1, max: 12, def: s.inputType === 'word' ? 6 : 4 })),
        ));
        c.appendChild(row(
            fld('Wrong tries', input(s, 'wrongTries', 'number', { min: 1, def: B.defaults.wrongTries })),
            fld('Cooldown (s)', input(s, 'cooldown', 'number', { min: 0, def: B.defaults.cooldown })),
        ));
        c.appendChild(input(s, 'resetOnFail', 'check', { label: 'After the lockout, reset the hint with a new code' }));
        return c;
    }

    function timeLockCard(s) {
        const c = card('Time lock', false);
        s.timeLock = isObj(s.timeLock) ? s.timeLock : {};
        const t = s.timeLock;
        c.appendChild(fld('Mode', input(t, 'mode', 'select', {
            def: 'off',
            options: opt([['off', 'Off'], ['ingame_hours', 'In-game hours'], ['real_time', 'Real time (days + hours)'], ['date_window', 'Date window'], ['timer_after_last_step', 'Timer after last step']]),
        })));
        const mode = t.mode || 'off';
        if (mode === 'off') return c;
        const num = (v) => (v === '' ? undefined : (isNaN(Number(v)) ? v : Number(v)));
        if (mode === 'ingame_hours' || mode === 'real_time') {
            c.appendChild(row(
                fld('Opens (hour)', input(t, 'opens', 'text', { parse: num, placeholder: '22' }), '22.5 = 22:30'),
                fld('Closes (hour)', input(t, 'closes', 'text', { parse: num, placeholder: '4' }), 'Wraps past midnight'),
            ));
        }
        if (mode === 'real_time') {
            const days = el('div', 'grid-checks');
            const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            t.days = Array.isArray(t.days) ? t.days : [];
            names.forEach((n, i) => {
                const l = el('label', 'chk');
                const cb = el('input');
                cb.type = 'checkbox';
                cb.checked = t.days.includes(i + 1);
                cb.onchange = () => {
                    t.days = t.days.filter((d) => d !== i + 1);
                    if (cb.checked) t.days.push(i + 1);
                    t.days.sort();
                    touch();
                };
                l.append(cb, el('span', '', n));
                days.appendChild(l);
            });
            c.appendChild(fld('Days (none = every day)', days));
        }
        if (mode === 'date_window') {
            c.appendChild(row(
                fld('Opens', input(t, 'opens', 'text', { placeholder: '2026-12-24 18:00' })),
                fld('Closes', input(t, 'closes', 'text', { placeholder: '2026-12-26 00:00' })),
            ));
        }
        if (mode === 'timer_after_last_step') {
            c.appendChild(row(
                fld('Timer (seconds)', input(t, 'seconds', 'number', { min: 0 })),
                fld('When it runs out', input(t, 'timerMode', 'select', { def: 'wait', rerender: false, options: opt([['wait', 'Wait: opens after'], ['expire', 'Expire: too late after']]) })),
            ));
        }
        c.appendChild(fld('Locked message', input(t, 'lockedMessage', 'text', { placeholder: 'Nothing here right now.' })));
        c.appendChild(input(t, 'hideWhileLocked', 'check', { label: 'Hide NPC / spot while locked' }));
        c.appendChild(input(t, 'comeBack', 'check', { label: 'Send a "come back at X" hint' }));
        return c;
    }

    function sceneCard(s) {
        const btn = el('button', 'btn small', 'Place scene here');
        const c = card('World scene', false, s.scene ? btn : null);
        btn.onclick = async () => {
            const pos = await post('builderPlace');
            if (pos && s.scene) { s.scene.coords = pos; touch(); renderCards(); }
        };
        const holder = { preset: s.scene ? s.scene.preset : '' };
        const presetSel = input(holder, 'preset', 'select', {
            rerender: false,
            options: [['', 'None']].concat(B.presets.map((p) => [p.value, p.label])),
        });
        presetSel.onchange = () => {
            if (!presetSel.value) delete s.scene;
            else {
                s.scene = isObj(s.scene) ? s.scene : { rearDoors: true, guards: 0, guardMode: 'calm', visibility: 'private', effects: {} };
                s.scene.preset = presetSel.value;
            }
            touch();
            renderCards();
            renderSide();
        };
        c.appendChild(fld('Preset', presetSel));
        if (!s.scene) return c;
        const sc = s.scene;
        sc.effects = isObj(sc.effects) ? sc.effects : {};
        if (sc.preset === 'armored_van') c.appendChild(input(sc, 'rearDoors', 'check', { label: 'Rear doors open', def: true }));
        c.appendChild(row(
            fld('Guards (0-4)', input(sc, 'guards', 'number', { min: 0, max: 4, def: 0 })),
            fld('Guard mode', input(sc, 'guardMode', 'select', { def: 'calm', rerender: false, options: opt([['calm', 'Calm'], ['hostile', 'Hostile'], ['dressing', 'Set dressing']]) })),
        ));
        c.appendChild(fld('Who sees it', input(sc, 'visibility', 'select', { def: 'private', rerender: false, options: opt([['private', 'Only the player on the step (private)'], ['shared', 'Everyone (shared)']]) })));
        const fx = el('div', 'grid-checks');
        [['smoke', 'Smoke'], ['sparks', 'Sparks'], ['flare', 'Flare']].forEach(([k, l]) => fx.appendChild(input(sc.effects, k, 'check', { label: l })));
        c.appendChild(fld('Effects', fx));
        c.appendChild(row(
            fld('Search area radius (m)', input(sc, 'searchRadius', 'number', { min: 0, def: 0 }), '0 = no blip'),
            fld('Search blip time (s)', input(sc, 'searchSeconds', 'number', { min: 0, def: 0 }), '0 = while on the step'),
        ));
        c.appendChild(coordsLine(sc, 'coords', 'Scene'));
        if (!sc.coords) c.appendChild(el('div', 'bd-empty', 'Not placed: uses the step\'s own spot.'));
        return c;
    }

    function dialogCard(s) {
        const add = el('button', 'btn small', 'Add line');
        const c = card('Dialog', true, add);
        s.dialog = Array.isArray(s.dialog) ? s.dialog : [];
        add.onclick = () => { s.dialog.push({ id: `line${s.dialog.length + 1}`, text: '', replies: [] }); touch(); renderCards(); };
        if (!s.dialog.length) c.appendChild(el('div', 'bd-empty', 'No lines yet. The first line is what the NPC says when you talk.'));
        s.dialog.forEach((line, li) => {
            line.replies = Array.isArray(line.replies) ? line.replies : [];
            const box = el('div', 'line-box');
            const head = el('div', 'line-head');
            head.appendChild(el('div', 'n', `Line ${li + 1}`));
            const idInp = input(line, 'id', 'text', { placeholder: 'line id' });
            idInp.style.maxWidth = '160px';
            head.appendChild(idInp);
            const sp = el('div');
            sp.style.flex = '1';
            head.appendChild(sp);
            const addR = el('button', 'btn small', 'Add reply');
            addR.disabled = line.replies.length >= 4;
            addR.onclick = () => { line.replies.push({ label: '', action: 'end' }); touch(); renderCards(); };
            const delL = el('button', 'btn small danger', 'Delete line');
            delL.onclick = () => { s.dialog.splice(li, 1); touch(); renderCards(); };
            head.append(addR, delL);
            box.appendChild(head);
            box.appendChild(input(line, 'text', 'textarea'));
            line.replies.forEach((r, ri) => {
                const rb = el('div', 'reply-box');
                rb.appendChild(fld(`Reply ${ri + 1}`, input(r, 'label', 'text', { placeholder: 'What the player says' })));
                rb.appendChild(fld('Action', input(r, 'action', 'select', {
                    def: 'end',
                    options: opt([['next_line', 'Next line'], ['give_clue', 'Give clue'], ['open_password', 'Open password'], ['open_shop', 'Open shop'], ['end', 'End']]),
                })));
                if (r.action === 'next_line') {
                    const ids = [['', 'Following line']].concat(s.dialog.map((l, k) => [l.id || String(k + 1), `Line ${k + 1}${l.id ? ' · ' + l.id : ''}`]));
                    rb.appendChild(fld('Goes to', input(r, 'next', 'select', { rerender: false, options: ids, parse: (v) => v || undefined })));
                } else if (r.action === 'open_shop') {
                    rb.appendChild(fld('Shop id', input(r, 'shop', 'text', { placeholder: s.shop || 'shop id' })));
                } else {
                    rb.appendChild(el('div'));
                }
                const del = el('button', 'btn small icon danger', '✕');
                del.onclick = () => { line.replies.splice(ri, 1); touch(); renderCards(); };
                rb.appendChild(del);
                const extra = el('div', 'extra');
                if (r.action === 'give_clue') {
                    extra.appendChild(input(r, 'clue', 'text', { placeholder: 'Clue text ({piece} = code piece)' }));
                    extra.appendChild(input(r, 'piece', 'check', { label: 'Carries a code piece (riddle)' }));
                    extra.appendChild(input(r, 'complete', 'check', { label: 'Finishes the step', def: true }));
                } else if (r.action === 'open_shop') {
                    extra.appendChild(input(r, 'receipt', 'check', { label: 'Purchase gives a receipt with a code piece' }));
                    extra.appendChild(input(r, 'complete', 'check', { label: 'Finishes the step' }));
                } else if (r.action === 'end') {
                    extra.appendChild(input(r, 'complete', 'check', { label: 'Finishes the step' }));
                }
                if (extra.children.length) rb.appendChild(extra);
                box.appendChild(rb);
            });
            c.appendChild(box);
        });
        return c;
    }

    function rewardsCard(s) {
        const add = el('button', 'btn small', 'Add item');
        const c = card('Rewards', false, add);
        s.rewards = Array.isArray(s.rewards) ? s.rewards : [];
        add.onclick = () => { s.rewards.push({ name: '', count: 1 }); touch(); renderCards(); };
        if (!s.rewards.length) c.appendChild(el('div', 'bd-empty', 'Items added to the player\'s own copy of the stash when it unlocks.'));
        s.rewards.forEach((r, i) => {
            const rr = el('div', 'reward-row');
            rr.appendChild(input(r, 'name', 'text', { placeholder: 'item name (money, lockpick...)' }));
            rr.appendChild(input(r, 'count', 'number', { min: 1, def: 1 }));
            const del = el('button', 'btn small icon danger', '✕');
            del.onclick = () => { s.rewards.splice(i, 1); touch(); renderCards(); };
            rr.appendChild(del);
            c.appendChild(rr);
        });
        return c;
    }

    function renderCards() {
        const wrap = $('bd-cards');
        const scroll = wrap.scrollTop;
        wrap.innerHTML = '';
        const s = B.hint.steps[B.sel];
        if (!s) {
            $('bd-kicker').textContent = B.hint.id ? `Hint #${B.hint.id}` : 'New hint';
            $('bd-title').textContent = 'No step selected';
            wrap.appendChild(el('div', 'bd-empty', 'Add a step on the left. Steps run in order for each character.'));
            return;
        }
        $('bd-kicker').textContent = `Step ${B.sel + 1} of ${B.hint.steps.length}`;
        $('bd-title').textContent = TYPE_LABEL[s.type] || s.type;
        wrap.appendChild(generalCard(s));
        if (s.type === 'password') wrap.appendChild(codeCard(s));
        if (s.type === 'stash') wrap.appendChild(rewardsCard(s));
        wrap.appendChild(timeLockCard(s));
        wrap.appendChild(sceneCard(s));
        if (s.type === 'npc') wrap.appendChild(dialogCard(s));
        wrap.scrollTop = scroll;
    }

    function renderBuilder() {
        renderSide();
        renderCards();
    }

    function builderOpen(d) {
        B.hints = Array.isArray(d.hints) ? d.hints : [];
        B.presets = d.presets || [];
        B.defaults = d.defaults || {};
        B.cinematicDefault = d.cinematicDefault !== false;
        const wanted = d.selectId ? B.hints.find((h) => h.id === d.selectId) : null;
        if (wanted) {
            loadHint(wanted); // "Edit in the builder" from the manage menu
        } else if (!d.resume || !B.hint) {
            loadHint(B.hints[0]);
        } else {
            renderBuilder();
        }
        show('builder');
    }
    $('bd-manage').onclick = () => post('builderManage');

    $('bd-hint').onchange = (e) => {
        const v = e.target.value;
        loadHint(v === 'new' ? null : B.hints.find((h) => String(h.id) === v));
    };
    $('bd-name').oninput = (e) => { B.hint.name = e.target.value; touch(); };
    $('bd-enabled').onchange = (e) => { B.hint.enabled = e.target.checked; touch(); };
    $('bd-auto').onchange = (e) => { B.hint.autoStart = e.target.checked; touch(); };
    $('bd-addbtn').onclick = () => {
        const type = $('bd-addtype').value;
        const s = { type, uid: uid() };
        if (type === 'npc') s.dialog = [{ id: 'start', text: '', replies: [{ label: 'Bye.', action: 'end' }] }];
        if (type === 'password') s.sources = { message: true, note: true, inspect: true, npc: true, receipt: true };
        B.hint.steps.push(s);
        B.sel = B.hint.steps.length - 1;
        touch();
        renderBuilder();
    };
    $('bd-place').onclick = async () => {
        const s = B.hint.steps[B.sel];
        if (!s) return;
        const pos = await post('builderPlace');
        if (!pos) return;
        s.coords = pos;
        touch();
        renderBuilder();
    };
    $('bd-preview').onclick = () => {
        const s = B.hint.steps[B.sel];
        if (s) post('builderPreview', { step: s });
    };
    $('bd-save').onclick = async () => {
        const res = await post('builderSave', { hint: B.hint });
        if (!res) return;
        B.hints = res.hints || B.hints;
        B.hint.id = res.id;
        const saved = B.hints.find((h) => h.id === res.id);
        const sel = B.sel;
        if (saved) loadHint(saved);
        B.sel = Math.min(sel, B.hint.steps.length - 1);
        setDirty(false);
        renderBuilder();
    };
    let deleteHintArmed = false;
    $('bd-delete').onclick = async () => {
        if (!B.hint.id) return;
        if (!deleteHintArmed) {
            deleteHintArmed = true;
            $('bd-delete').textContent = 'Click again';
            setTimeout(() => { deleteHintArmed = false; $('bd-delete').textContent = 'Delete hint'; }, 3000);
            return;
        }
        deleteHintArmed = false;
        $('bd-delete').textContent = 'Delete hint';
        const res = await post('builderDelete', { id: B.hint.id });
        if (!res) return;
        B.hints = res.hints || [];
        loadHint(B.hints[0]);
    };
    $('bd-reset').onclick = () => { if (B.hint.id) post('builderResetMe', { id: B.hint.id }); };
    $('bd-hide').onclick = () => post('builderHide');
    $('bd-close').onclick = () => close();

    // ---------------- Input ----------------
    window.addEventListener('keydown', (e) => {
        if (!current) return;
        if (e.key === 'Escape') return close();
        if (current === 'dialog') {
            if (/^[1-4]$/.test(e.key)) dlgReply(Number(e.key));
            else if (e.key === ' ' || e.key === 'Enter') dlgFinishTyping();
        } else if (current === 'keypad') {
            if (/^[0-9]$/.test(e.key)) { flash(e.key); kpKey(e.key); }
            else if (e.key === 'Enter') { flash('ok'); kpKey('ok'); }
            else if (e.key === 'Backspace') {
                if (!kp.busy) { click(); kp.value = kp.value.slice(0, -1); kpRender(); }
            } else if (e.key === 'Delete') { flash('clr'); kpKey('clr'); }
        } else if (current === 'word') {
            if (e.key === 'Enter') wdSubmit();
        } else if (current === 'inspect') {
            if (e.key === 'e' || e.key === 'E') close();
        }
    });

    // ---------------- Messages from Lua ----------------
    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.accent) document.documentElement.style.setProperty('--accent', d.accent);
        switch (d.action) {
            case 'keypad': return kpOpen(d);
            case 'word': return wdOpen(d);
            case 'dialog': return dlgOpen(d);
            case 'dialogLine': return dlgLine(d);
            case 'note': return noteOpen(d);
            case 'inspect': return inspectOpen(d);
            case 'builder': return builderOpen(d);
            case 'close': return close(false);
        }
    });
})();
