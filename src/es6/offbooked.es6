import "./lib/import-jquery";
import bootbox from "bootbox/bootbox.all";
import Mustache from "mustache/mustache";

const pageId = "offbooked";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  registerCallback();
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
} else {
  domLoaded();
}

const registerCallback = () => {
  $(".btn-offbooked-cancel").on("click", (e) => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    let url = $target.data("url");
    let orderId = $target.data("order-id");
    let bookingDate = $target.data("booking-date");
    console.log(`remove clicked: orderId(${orderId}) url(${url})`);

    let modal = bootbox.confirm({
      title: Mustache.render($("#template-offbooked-modal-remove-title").html()),
      message: Mustache.render($("#template-offbooked-modal-remove-message").html(), { "bookingDate": bookingDate }),
      locale: "ko",
      buttons: {
        confirm: { label: "예약을 취소합니다", className: "opencloset-btn-next" },
        cancel:  { label: "닫기", className: "opencloset-btn-cancel"  },
      },
      callback: (result) => {
        if (result) {
          // cancel order
          console.log(`have to delete: orderId(${orderId})`);

          // success
          window.location = `${$target.data("url")}`;
        }
        else {
          // do nothing
        }
        return true;
      }
    });

    return false;
  });

  $(".btn-offbooked-next").on("click", e => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    // success
    window.location = `${$target.data("url")}`;

    return false;
  });
};
