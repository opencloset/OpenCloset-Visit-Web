import './import-jquery';
import perfectScrollbar from 'perfect-scrollbar/dist/perfect-scrollbar';

const domLoaded = () => {
  if ( $('#sidebar').length == 0 )
    return;

  new perfectScrollbar('#sidebar', {
    wheelSpeed: 2,
    wheelPropagation: true,
    minScrollbarLength: 20
  });

  $('#sidebarCollapse').on('click', function () {
    $('#sidebar, #content').toggleClass('active');
    $('.collapse.in').toggleClass('in');
    $('a[aria-expanded=true]').attr('aria-expanded', 'false');
  });

  var sidebarActive = function () {
    var paths = window.location.pathname.split('/');
    var menu1;
    var menu2;
    $('#sidebar li').removeClass('active');
    $('#sidebar li li').removeClass('active');
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
      $(`#sidebar li.sidebar-${menu1}`).addClass('active');
      if (menu2) {
        $(`#sidebar li.sidebar-${menu1} ul`).removeClass('collapse');
        $(`#sidebar li.sidebar-${menu1} li.sidebar-${menu1}-${menu2}`).addClass('active');
      }
    }
  };
  sidebarActive();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
}
else {
  domLoaded();
}
