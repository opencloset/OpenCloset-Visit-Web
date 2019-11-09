import './import-jquery';

const domLoaded = () => {
  var navHeaderActive = function () {
    var paths = window.location.pathname.split('/');
    var menu1;
    var menu2;
    $('.header ul.nav .nav-link').removeClass('active');
    if ( window.location.pathname == '/' ) {
      menu1 = 'home';
    }
    else {
      if (paths[1]) {
        menu1 = paths[1];
        if (paths[2]) {
          menu2 = paths[2];
        }
      }
    }
    if (menu1) {
      $(`.header ul.nav .nav-link.nav-header-${menu1}`).addClass('active');
    }
  };
  navHeaderActive();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
}
else {
  domLoaded();
}
