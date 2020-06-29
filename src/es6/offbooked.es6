import "./lib/import-jquery";
import bootbox from "bootbox/bootbox.all";
import session from "./lib/session";
import Mustache from "mustache/mustache";

const pageId = "offbooked";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  registerCallback();
  clearSession();
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

    let finishUrl = $target.data("finish-url");
    let apiUrl = $target.data("api-url");
    let url1 = $target.data("url1");
    let url2 = $target.data("url2");
    let orderId = $target.data("order-id");
    let bookingDate = $target.data("booking-date");
    let reqUrl = apiUrl + url1 + orderId + url2;

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
          // have to delete: orderId(${orderId})

          fetch(reqUrl, {
            method: "DELETE",
            headers: {
              "Accept": "application/json",
              "Content-Type": "application/json",
            },
          })
            .then(response => {
              if (!response.ok) {
                throw Error(response.statusText);
              }
              return response.json();
            })
            .then(response => {
              // success
              window.location = finishUrl;
            })
            .catch(error => {
              console.log(error);
            });
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

const clearSession = () => {
  let phone = $(`#${pageId}`).data("user-info-phone");
  session.clear(phone);
}
