(function(){var d=null;try{d=JSON.parse(localStorage.getItem("darkMode"))}catch(e){}
if(d===null)d=matchMedia("(prefers-color-scheme: dark)").matches;
document.documentElement.classList.add(d?"ct-dark":"ct-light");
function t(){if(/Invidious/.test(document.title))document.title=document.title.replace(/Invidious/g,"CloudTube")}
t();document.addEventListener("DOMContentLoaded",t);})();
