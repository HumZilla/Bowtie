/* Bowtie referral context: browser-tab scoped, no buyer PII or cross-site tracking. */
(function (root) {
  'use strict';
  const KEY='bowtie_referral_code_v1';
  function clean(value) {
    const s=String(value||'').trim();
    return s.length>0&&s.length<=30&&!/[\x00-\x1f\x7f<>]/.test(s)?s:'';
  }
  function stored() {
    try { return clean(root.sessionStorage.getItem(KEY)); } catch (_) { return ''; }
  }
  function set(value) {
    const code=clean(value);
    try { if(code) root.sessionStorage.setItem(KEY,code); else root.sessionStorage.removeItem(KEY); } catch (_) {}
    return code;
  }
  function current(hash) {
    const p=new URLSearchParams(String(hash===undefined?root.location.hash:hash).replace(/^#/,''));
    // Explicit ref in URL takes precedence. An empty ref clears the session.
    if(p.has('ref')) return set(p.get('ref'));
    return stored();
  }
  function withRef(url,hash) {
    const ref=current(hash);
    if(!ref)return url;
    const parts=url.split('#');
    const params=new URLSearchParams(parts[1]||'');
    if(!params.has('ref'))params.set('ref',ref);
    return parts[0]+'#'+params.toString();
  }
  root.BowtieReferral={current,set,clear:()=>set(''),withRef};
})(window);
