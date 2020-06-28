import "./lib/import-jquery";
import bootbox from "bootbox/bootbox.all";
import Mustache from "mustache/mustache";
import opencloset from "./lib/opencloset";

const pageId = "offlist";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  opencloset.convertIdToString(".opencloset-id2str");
  registerCallback();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
}
else {
  domLoaded();
}

const registerCallback = () => {
  $(".btn-offlist-order-edit").on("click", (e) => {
    e.preventDefault();
    let $target = $(e.target);
    let apiUrl = $target.closest(".reserved-list").data("api-url");
    let orderId = $target.closest(".card.reserved").data("order-id");
    return false;
  });

  $(".btn-offlist-order-remove").on("click", (e) => {
    e.preventDefault();
    let $target = $(e.target);
    let apiUrl = $target.closest(".reserved-list").data("api-url");
    let url1 = $target.data("url1");
    let url2 = $target.data("url2");
    let $card = $target.closest(".card.reserved");
    let orderId = $card.data("order-id");
    let bookingYmd = $card.data("booking-ymd");
    let bookingHms = $card.data("booking-hms");
    let reqUrl = apiUrl + url1 + orderId + url2;

    let modal = bootbox.confirm({
      title: Mustache.render($("#template-offlist-modal-remove-title").html()),
      message: Mustache.render($("#template-offlist-modal-remove-message").html(), { "bookingYmd": bookingYmd, "bookingHms": bookingHms }),
      locale: "ko",
      buttons: {
        confirm: { label: "삭제", className: "btn-primary" },
        cancel:  { label: "취소", className: "btn-danger"  },
      },
      callback: (result) => {
        if (result) {
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
              $card.remove();
              if ( $(".card.reserved").length == 0 ) {
                // all bookings are removed
                $(".offlist-booking-new-bottom-button").removeClass("d-flex").addClass("d-none");
                $(".offlist-booking-new-bottom-message").removeClass("d-none");
              }
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
    modal.animate({ scrollTop: 0 }, "slow");

    return false;
  });

  $(".btn-offlist-next").on("click", e => {
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
