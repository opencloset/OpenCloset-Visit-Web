import "./lib/import-jquery";
import moment from "moment/src/moment";
import Mustache from "mustache/mustache";

const pageId = "offdate";

const domLoaded = () => {
  if (!$(`#page-${pageId}`).length) return;

  registerCallbackDatetimepickerChange();
  registerCallbackBookingTimeListClick();
  registerCallbackNextClick();

  let ymd = $("#bookingYmd").val();
  if (!ymd) {
    ymd = moment().format("YYYY-MM-DD");
    $("#bookingYmd").val(ymd);
  }
  updateAvailableBookingList(ymd);
};

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", domLoaded);
} else {
  domLoaded();
}

const registerCallbackDatetimepickerChange = () => {
  // https://stackoverflow.com/questions/31858920/jquery-bootstrap-datetimepicker-change-event
  $("#offdateDatetimepicker").on("dp.change", e => {
    // use specific "YYYY-MM-DD" rather than e.date._f
    // since somtimes e.date._f is not ready to use
    let formatedValue = e.date.format("YYYY-MM-DD");
    updateAvailableBookingList(formatedValue);
  });
};

const registerCallbackBookingTimeListClick = () => {
  $(".offdate-booking-hm-list input[type=radio]").on("click", e => {
    updateNextButton();
    $(".custom-control").removeClass("selected");
    $(e.target)
      .closest(".custom-control")
      .addClass("selected");
  });
};

const registerCallbackNextClick = () => {
  $("#btn-offdate-next").on("click", e => {
    e.preventDefault();

    // .disabled 클래스일 경우 클릭 무시
    let $target = $(e.target);
    if ($target.hasClass("disabled")) {
      return false;
    }

    let bookingId = $("input[name=booking-hm]:checked").val();
    if (!(bookingId && bookingId > 0)) {
      return false;
    }

    let reqUrl = new URL($target.data("url"), window.location.origin);
    reqUrl.searchParams.set("booking_id", bookingId);

    // success
    window.location = reqUrl.href;

    return false;
  });
};

const updateAvailableBookingList = ymd => {
  if (ymd.match(/^\d{4}-\d{2}-\d{2}$/) === null) {
    return;
  }

  let templateSuccess = $("#template-booking-list-success").html();
  let templateFailure = $("#template-booking-list-failure").html();
  let $bookingHmList = $(".offdate-booking-hm-list");
  let now = moment();

  let reqUrl = new URL(
    `/api/gui/booking-list.json${window.location.search}`,
    window.location.origin,
  );
  reqUrl.searchParams.set("ymd", ymd);
  reqUrl.searchParams.set("include_empty", 1);
  fetch(reqUrl, { method: "GET" })
    .then(response => {
      if (!response.ok) {
        throw Error(response.statusText);
      }
      return response;
    })
    .then(response => response.json())
    .then(resData => {
      let countAvailable = 0;
      resData.forEach(val => {
        let valDate = moment(val.date);
        let isRemain = val.slot > val.user_count;
        let isNew = now.unix() < valDate.unix();

        val.hm = val.date.substring(11, 16);
        val.remainSlot = isRemain ? val.slot - val.user_count : 0;
        val.breakTime = false;
        val.display = false;
        val.old = !isNew;

        // break time
        let weekDay = valDate.day();
        switch (weekDay) {
          case 1: // Mon
          case 2: // Tue
          case 3: // Wed
          case 4: // Thu
          case 5: // Fri
            let hm = valDate.format("HH:mm");
            switch (hm) {
              case "15:30":
              case "16:00":
              case "16:30":
                val.breakTime = true;
                val.remainSlot = 0;
            }
          case 0: // Sun
          case 6: // Sat
        }

        // display
        {
          let hmInt = parseInt(valDate.format("Hmm"), 10);
          switch (weekDay) {
            case 1: // Mon
            case 2: // Tue
            case 3: // Wed
            case 4: // Thu
            case 5: // Fri
              if (900 <= hmInt && hmInt <= 1900) {
                val.display = true;
              }
            case 0: // Sun
            case 6: // Sat
              if (900 <= hmInt && hmInt <= 1700) {
                val.display = true;
              }
          }
        }

        if (isRemain && isNew) {
          countAvailable++;
        }
      });
      if (countAvailable <= 0) {
        $bookingHmList.html(templateFailure);
        updateNextButton();
        return;
      }

      $bookingHmList.html(
        Mustache.render(templateSuccess, { bookingList: resData }),
      );
      registerCallbackBookingTimeListClick();
      updateNextButton();
    })
    .catch(error => {
      $bookingHmList.html(templateFailure);
      updateNextButton();
    });
};

const updateNextButton = () => {
  let bookingId = $("input[name=booking-hm]:checked").val();

  let $nextBtn = $("#btn-offdate-next");
  if (bookingId && bookingId > 0) {
    $nextBtn.html($nextBtn.data("label2")).removeClass("disabled");
  } else {
    $nextBtn.html($nextBtn.data("label1")).addClass("disabled");
  }
};
